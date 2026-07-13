#if RUNTIME_STUB
import Foundation

/// Records method calls and returns stubbed values.
/// Supports three modes: normal (dispatch to stubs), recording (capture calls),
/// and verifying (check call log).
class StubRecorder: @unchecked Sendable {
    init() {}

    private let lock = NSRecursiveLock()

    enum Mode {
        case normal
        case recording
        case verifying
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
    private var storedNames: [Int: String] = [:]

    // Runtime marshalling descriptors, keyed by witness-table requirement index.
    private var storedRuntimeMethods: [Int: RuntimeMethodDescriptor] = [:]
    var runtimeMethods: [Int: RuntimeMethodDescriptor] { withLock { storedRuntimeMethods } }

    // Call log
    private var storedCalls: [RecordedCall] = []
    var calls: [RecordedCall] { withLock { storedCalls } }

    // Last recording (set during recording mode)
    private var storedLastRecording: RecordedCall?
    var lastRecording: RecordedCall? {
        get { withLock { storedLastRecording } }
        set { withLock { storedLastRecording = newValue } }
    }

    private var storedVerificationRecordings: [RecordedCall] = []
    var verificationRecordings: [RecordedCall] {
        get { withLock { storedVerificationRecordings } }
        set { withLock { storedVerificationRecordings = newValue } }
    }

    struct StubEntry {
        enum Behavior {
            case immediate(([Any]) throws -> Any)
            case suspending(([Any]) async throws -> Any)
        }

        let matchers: [ParameterMatcher]
        let diagnosticSignature: String
        let behavior: Behavior
        let action: (([Any]) -> Void)?
        let isFallback: Bool
    }

    // MARK: - Method name registration

    func setName(_ name: String, for index: Int) {
        withLock { storedNames[index] = name }
    }

    func setRuntimeMethod(_ method: RuntimeMethodDescriptor, for index: Int) {
        withLock {
            storedRuntimeMethods[index] = method
            storedNames[index] = method.name
        }
    }

    func runtimeMethod(for index: Int) -> RuntimeMethodDescriptor? {
        withLock { storedRuntimeMethods[index] }
    }

    // MARK: - Dispatch (called by witness table thunks)

    func dispatch(method: Int, args: [Any]) -> Any {
        let snapshot = withLock {
            (
                mode: storedMode,
                name: storedNames[method] ?? "method_\(method)",
                entries: storedStubs[method]
            )
        }

        switch snapshot.mode {
        case .recording:
            withLock {
                storedLastRecording = RecordedCall(
                    methodIndex: method,
                    name: snapshot.name,
                    args: args,
                    matchers: []
                )
            }
            return zeroValue // thunk handles the actual return type

        case .verifying:
            let recording = RecordedCall(methodIndex: method, name: snapshot.name, args: args, matchers: [])
            withLock {
                storedLastRecording = recording
                storedVerificationRecordings.append(recording)
            }
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
                entry.action?(args)
                return try! handler(args)
            case .suspending:
                fatalError(
                    "[TestDoubles] A suspending handler was selected for synchronous dispatch of \(snapshot.name). " +
                    "Use it only with an async RuntimeStub requirement."
                )
            }
        }
    }

    // MARK: - Throwing stubs

    /// Register a stub that throws.
    func addThrowingStub(method: Int, matchers: [ParameterMatcher], handler: @escaping ([Any]) throws -> Any) {
        withLock {
            storedStubs[method, default: []].append(StubEntry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignatureLocked(method: method, matchers: matchers),
                behavior: .immediate(handler),
                action: nil,
                isFallback: false
            ))
        }
    }

    /// Dispatches a throwing call through the best matching immediate behavior.
    /// Returns `nil` when no configured behavior matches.
    func dispatchThrowing(method: Int, args: [Any]) -> Result<Any, any Error>? {
        let snapshot = withLock {
            (
                mode: storedMode,
                name: storedNames[method] ?? "method_\(method)",
                entries: storedStubs[method]
            )
        }

        switch snapshot.mode {
        case .recording:
            withLock {
                storedLastRecording = RecordedCall(
                    methodIndex: method,
                    name: snapshot.name,
                    args: args,
                    matchers: []
                )
            }
            return .success(zeroValue)

        case .verifying:
            let recording = RecordedCall(methodIndex: method, name: snapshot.name, args: args, matchers: [])
            withLock {
                storedLastRecording = recording
                storedVerificationRecordings.append(recording)
            }
            return .success(zeroValue)

        case .normal:
            break
        }

        guard let entries = snapshot.entries,
              let entry = bestMatchingEntry(for: args, in: entries) else {
            return nil
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
            entry.action?(args)
            do {
                return .success(try handler(args))
            } catch {
                return .failure(error)
            }
        case .suspending:
            fatalError(
                "[TestDoubles] A suspending handler was selected for synchronous throwing dispatch of \(snapshot.name). " +
                "Use it only with an async RuntimeStub requirement."
            )
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
                    "[TestDoubles] Suspending handlers require an async RuntimeStub requirement. " +
                    "CompiledStub and synchronous requirements support only immediate handlers."
                )
            }
            storedStubs[method, default: []].append(StubEntry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignatureLocked(method: method, matchers: matchers),
                behavior: .suspending(handler),
                action: nil,
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
    ) -> (([Any]) async throws -> Any)? {
        let snapshot = withLock {
            (
                mode: storedMode,
                name: storedNames[method] ?? "method_\(method)",
                entries: storedStubs[method]
            )
        }

        guard case .normal = snapshot.mode, let entries = snapshot.entries else {
            return nil
        }

        guard let bestEntry = bestMatchingEntry(for: args, in: entries),
              case .suspending(let handler) = bestEntry.behavior else {
            return nil
        }

        withLock {
            storedCalls.append(RecordedCall(
                methodIndex: method,
                name: snapshot.name,
                args: args,
                matchers: []
            ))
        }
        return handler
    }

    // MARK: - Stub registration

    func addStub(
        method: Int,
        matchers: [ParameterMatcher],
        returnValue: @escaping ([Any]) -> Any,
        action: (([Any]) -> Void)? = nil,
        isFallback: Bool = false
    ) {
        withLock {
            storedStubs[method, default: []].append(StubEntry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignatureLocked(method: method, matchers: matchers),
                behavior: .immediate(returnValue),
                action: action,
                isFallback: isFallback
            ))
        }
    }

    // MARK: - Verification queries

    func callCount(method: Int, matchers: [ParameterMatcher] = []) -> Int {
        let calls = withLock { storedCalls }
        return calls.filter { call in
            call.methodIndex == method && (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }.count
    }

    func reset() {
        withLock { storedCalls.removeAll() }
    }

    // MARK: - Matching

    private func matchArgs(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }

    /// Returns the first registered entry among those with the highest matcher
    /// specificity. Registration kind never affects precedence.
    private func bestMatchingEntry(for args: [Any], in entries: [StubEntry]) -> StubEntry? {
        var bestEntry: StubEntry?
        var bestSpecificity = -1
        var bestPriority = -1
        for entry in entries where entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
            let specificity = entry.matchers.reduce(0) { $0 + $1.specificity }
            let priority = entry.isFallback ? 0 : 1
            if specificity > bestSpecificity ||
                (specificity == bestSpecificity && priority > bestPriority) {
                bestSpecificity = specificity
                bestPriority = priority
                bestEntry = entry
            }
        }
        return bestEntry
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

        lines.append("")
        lines.append("Suggested:")
        lines.append("  \(suggestedStubSnippet(name: name, args: args))")
        return lines.joined(separator: "\n")
    }

    private func diagnosticSignatureLocked(method: Int, matchers: [ParameterMatcher]) -> String {
        let name = storedNames[method] ?? "method_\(method)"
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

    // Sentinel value for recording/verifying mode returns
    private var zeroValue: Any { 0 as Int }

    @discardableResult
    private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

// MARK: - RecordedCall

public struct RecordedCall {
    public let methodIndex: Int
    public let name: String
    public let args: [Any]
    var matchers: [ParameterMatcher]
}
#endif
