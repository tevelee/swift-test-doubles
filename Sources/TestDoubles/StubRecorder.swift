import Foundation

/// Records method calls and returns stubbed values.
/// Uses normal dispatch and a temporary capture mode shared by stubbing and
/// verification.
class StubRecorder: @unchecked Sendable {
    init() {}

    private let lock = NSRecursiveLock()

    enum Mode {
        case normal
        case capturing
    }

    private var storedMode: Mode = .normal
    var mode: Mode {
        get { withLock { storedMode } }
        set { withLock { storedMode = newValue } }
    }

    // Stub storage preserves registration order across every behavior kind so
    // matcher specificity is resolved consistently for immediate, throwing,
    // and suspending handlers.
    private var storedStubs: [Int: [StubEntry]] = [:]

    // Runtime marshalling descriptors, keyed by witness-table requirement index.
    private var storedRuntimeMethods: [Int: RuntimeMethodDescriptor] = [:]

    // Call log
    private var storedCalls: [RecordedCall] = []

    // Last invocation observed in capture mode.
    private var storedLastRecording: RecordedCall?
    var lastRecording: RecordedCall? {
        get { withLock { storedLastRecording } }
        set { withLock { storedLastRecording = newValue } }
    }

    struct StubEntry {
        enum Behavior {
            case immediate(([Any]) throws -> Any)
            case suspending(([Any]) async throws -> Any)
        }

        let matchers: [ParameterMatcher]
        let diagnosticSignature: String
        let behavior: Behavior
        let isFallback: Bool
    }

    enum AsyncDispatch {
        case placeholder
        case immediate(Result<Any, any Error>)
        case suspending(([Any]) async throws -> Any)
    }

    func setRuntimeMethod(_ method: RuntimeMethodDescriptor, for index: Int) {
        withLock {
            storedRuntimeMethods[index] = method
        }
    }

    func runtimeMethod(for index: Int) -> RuntimeMethodDescriptor? {
        withLock { storedRuntimeMethods[index] }
    }

    // MARK: - Dispatch (called by witness table thunks)

    func dispatch(method: Int, args: [Any]) throws -> Any {
        let snapshot = withLock {
            (
                mode: storedMode,
                name: storedRuntimeMethods[method]?.name ?? "method_\(method)",
                entries: storedStubs[method]
            )
        }

        switch snapshot.mode {
        case .capturing:
            recordPlaceholder(method: method, name: snapshot.name, args: args)
            return zeroValue

        case .normal:
            guard let entries = snapshot.entries else {
                fatalError(diagnosticMessage(
                    title: "No stub configured",
                    method: method,
                    name: snapshot.name,
                    args: args,
                    entries: []
                ))
            }
            guard let entry = bestMatchingEntry(for: args, in: entries) else {
                fatalError(diagnosticMessage(
                    title: "No matching stub",
                    method: method,
                    name: snapshot.name,
                    args: args,
                    entries: entries
                ))
            }
            withLock {
                storedCalls.append(RecordedCall(
                    methodIndex: method,
                    name: snapshot.name,
                    args: args,
                    matchers: []
                ))
            }
            switch entry.behavior {
            case .immediate(let handler):
                return try handler(args)
            case .suspending:
                fatalError(
                    "[TestDoubles] A suspending handler was selected for synchronous dispatch of \(snapshot.name). " +
                    "Use it only with an async Stub requirement."
                )
            }
        }
    }

    // MARK: - Async stubs

    func addAsyncStub(
        method: Int,
        matchers: [ParameterMatcher],
        handler: @escaping ([Any]) async throws -> Any
    ) {
        withLock {
            guard storedRuntimeMethods[method]?.isAsync == true else {
                preconditionFailure(
                    "[TestDoubles] Suspending handlers require an async Stub requirement. " +
                    "Synchronous requirements support only immediate handlers."
                )
            }
            storedStubs[method, default: []].append(StubEntry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignatureLocked(method: method, matchers: matchers),
                behavior: .suspending(handler),
                isFallback: false
            ))
        }
    }

    /// Selects and records a suspending handler without invoking it under the
    /// recorder lock. Recording and verification continue through the immediate
    /// dispatch path so their placeholder-return behavior remains synchronous.
    func prepareAsyncDispatch(
        method: Int,
        args: [Any]
    ) -> AsyncDispatch {
        let snapshot = withLock {
            (
                mode: storedMode,
                name: storedRuntimeMethods[method]?.name ?? "method_\(method)",
                entries: storedStubs[method]
            )
        }

        switch snapshot.mode {
        case .capturing:
            recordPlaceholder(method: method, name: snapshot.name, args: args)
            return .placeholder
        case .normal:
            break
        }

        guard let entries = snapshot.entries else {
            fatalError(diagnosticMessage(
                title: "No stub configured",
                method: method,
                name: snapshot.name,
                args: args,
                entries: []
            ))
        }
        guard let bestEntry = bestMatchingEntry(for: args, in: entries) else {
            fatalError(diagnosticMessage(
                title: "No matching stub",
                method: method,
                name: snapshot.name,
                args: args,
                entries: entries
            ))
        }

        withLock {
            storedCalls.append(RecordedCall(
                methodIndex: method,
                name: snapshot.name,
                args: args,
                matchers: []
            ))
        }
        switch bestEntry.behavior {
        case .immediate(let handler):
            do {
                return .immediate(.success(try handler(args)))
            } catch {
                return .immediate(.failure(error))
            }
        case .suspending(let handler):
            return .suspending(handler)
        }
    }

    // MARK: - Stub registration

    func addStub(
        method: Int,
        matchers: [ParameterMatcher],
        returnValue: @escaping ([Any]) throws -> Any,
        isFallback: Bool = false
    ) {
        withLock {
            storedStubs[method, default: []].append(StubEntry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignatureLocked(method: method, matchers: matchers),
                behavior: .immediate(returnValue),
                isFallback: isFallback
            ))
        }
    }

    // MARK: - Verification queries

    func callCount(method: Int, matchers: [ParameterMatcher] = []) -> Int {
        let calls = withLock { storedCalls }
        var count = 0
        for call in calls where call.methodIndex == method {
            guard matchers.isEmpty || argumentsMatch(call.args, against: matchers) else {
                continue
            }
            commitCaptures(in: call.args, against: matchers)
            count += 1
        }
        return count
    }

    // MARK: - Matching

    private func argumentsMatch(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }

    private func commitCaptures(in args: [Any], against matchers: [ParameterMatcher]) {
        zip(args, matchers).forEach { value, matcher in
            matcher.commit(value: value)
        }
    }

    /// Returns the first registered entry among those with the highest matcher
    /// specificity. Registration kind never affects precedence.
    private func bestMatchingEntry(
        for args: [Any],
        in entries: [StubEntry]
    ) -> StubEntry? {
        var bestEntry: StubEntry?
        var bestSpecificity = -1
        var bestPriority = -1
        for entry in entries where entry.matchers.isEmpty || argumentsMatch(args, against: entry.matchers) {
            let specificity = entry.matchers.reduce(0) { $0 + $1.specificity }
            let priority = entry.isFallback ? 0 : 1
            if specificity > bestSpecificity ||
                (specificity == bestSpecificity && priority > bestPriority) {
                bestSpecificity = specificity
                bestPriority = priority
                bestEntry = entry
            }
        }
        if let bestEntry {
            commitCaptures(in: args, against: bestEntry.matchers)
        }
        return bestEntry
    }

    private func recordPlaceholder(method: Int, name: String, args: [Any]) {
        withLock {
            storedLastRecording = RecordedCall(
                methodIndex: method,
                name: name,
                args: args,
                matchers: []
            )
        }
    }

    private func diagnosticMessage(
        title: String,
        method: Int,
        name: String,
        args: [Any],
        entries: [StubEntry]
    ) -> String {
        var lines: [String] = [
            "[TestDoubles] \(title) for \(name)",
            "",
            "Actual:",
        ]
        if args.isEmpty {
            lines.append("  <no arguments>")
        } else {
            for (index, arg) in args.enumerated() {
                lines.append("  arg\(index): \(String(reflecting: arg))")
            }
        }

        lines.append("")
        lines.append("Registered stubs:")
        if entries.isEmpty {
            lines.append("  <none>")
        } else {
            for entry in entries {
                lines.append("  \(entry.diagnosticSignature)")
            }
        }

        if name.hasPrefix("requirement_") == false {
            lines.append("")
            lines.append("Suggested:")
            lines.append("  \(suggestedStubSnippet(name: name, args: args))")
        }
        return lines.joined(separator: "\n")
    }

    private func diagnosticSignatureLocked(method: Int, matchers: [ParameterMatcher]) -> String {
        let name = storedRuntimeMethods[method]?.name ?? "method_\(method)"
        let matcherList = matchers.map(\.diagnosticDescription).joined(separator: ", ")
        return "\(name)(\(matcherList))"
    }

    private func suggestedStubSnippet(name: String, args: [Any]) -> String {
        let invocation = suggestedInvocation(name: name, args: args)
        return "stub.when { $0.\(invocation) }.returns(...)"
    }

    private func suggestedInvocation(name: String, args: [Any]) -> String {
        guard args.isEmpty == false else { return name }
        let matchers = args.map { "equal(\(swiftLiteralDescription($0)))" }

        guard let open = name.firstIndex(of: "("),
              name.last == ")" else {
            return "\(name)(\(matchers.joined(separator: ", ")))"
        }

        let base = String(name[..<open])
        let labelText = name[name.index(after: open)..<name.index(before: name.endIndex)]
        let labels = labelText
            .split(separator: ":", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init)
        guard labels.count == matchers.count else {
            return "\(base)(\(matchers.joined(separator: ", ")))"
        }

        let arguments = zip(labels, matchers).map { label, matcher in
            label == "_" ? matcher : "\(label): \(matcher)"
        }.joined(separator: ", ")
        return "\(base)(\(arguments))"
    }

    private func swiftLiteralDescription(_ value: Any) -> String {
        switch value {
        case let value as String:
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        case let value as Character:
            return "\"\(value)\""
        default:
            return String(describing: value)
        }
    }

    // Sentinel value for capture mode returns.
    private var zeroValue: Any { 0 as Int }

    @discardableResult
    private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

// MARK: - RecordedCall

struct RecordedCall {
    let methodIndex: Int
    let name: String
    let args: [Any]
    var matchers: [ParameterMatcher]

    var resolvedMatchers: [ParameterMatcher] {
        matchers.isEmpty
            ? args.map { DescriptionMatcher(value: $0) }
            : matchers
    }
}
