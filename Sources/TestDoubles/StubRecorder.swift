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

    // Stub storage: method index → [(matchers, returnValue, action)]
    private var storedStubs: [Int: [StubEntry]] = [:]
    private var storedAsyncStubs: [Int: [AsyncStubEntry]] = [:]
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
        let matchers: [ParameterMatcher]
        let diagnosticSignature: String
        let returnValue: ([Any]) -> Any
        let action: (([Any]) -> Void)?
    }

    struct AsyncStubEntry {
        let matchers: [ParameterMatcher]
        let handler: ([Any]) async throws -> Any
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
            // Best-match: prefer entries with the most specific matchers.
            // Specificity = number of non-any matchers. Higher is better.
            var bestEntry: StubEntry?
            var bestSpecificity = -1
            for entry in entries {
                if entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
                    let specificity = entry.matchers.reduce(0) { $0 + $1.specificity }
                    if specificity > bestSpecificity {
                        bestSpecificity = specificity
                        bestEntry = entry
                    }
                }
            }
            guard let entry = bestEntry else {
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
            entry.action?(args)
            return entry.returnValue(args)
        }
    }

    // MARK: - Throwing stubs

    private var storedThrowingStubs: [Int: [ThrowingStubEntry]] = [:]
    var throwingStubs: [Int: [ThrowingStubEntry]] { withLock { storedThrowingStubs } }

    struct ThrowingStubEntry {
        let matchers: [ParameterMatcher]
        let handler: ([Any]) throws -> Any
    }

    /// Register a stub that throws.
    func addThrowingStub(method: Int, matchers: [ParameterMatcher], handler: @escaping ([Any]) throws -> Any) {
        withLock {
            storedThrowingStubs[method, default: []].append(
                ThrowingStubEntry(matchers: matchers, handler: handler)
            )
        }
    }

    /// Dispatch a throwing call. Returns nil if no throwing stub is registered.
    func dispatchThrowing(method: Int, args: [Any]) -> Result<Any, any Error>? {
        let snapshot = withLock {
            (
                mode: storedMode,
                name: storedNames[method] ?? "method_\(method)",
                entries: storedThrowingStubs[method]
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

        guard let entries = snapshot.entries else { return nil }
        for entry in entries {
            if entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
                withLock {
                    storedCalls.append(RecordedCall(
                        methodIndex: method,
                        name: snapshot.name,
                        args: args,
                        matchers: []
                    ))
                }
                do {
                    return .success(try entry.handler(args))
                } catch {
                    return .failure(error)
                }
            }
        }
        return nil
    }

    // MARK: - Async stubs

    func addAsyncStub(
        method: Int,
        matchers: [ParameterMatcher],
        handler: @escaping ([Any]) async throws -> Any
    ) {
        withLock {
            storedAsyncStubs[method, default: []].append(
                AsyncStubEntry(matchers: matchers, handler: handler)
            )
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
                entries: storedAsyncStubs[method]
            )
        }

        guard case .normal = snapshot.mode, let entries = snapshot.entries else {
            return nil
        }

        var bestEntry: AsyncStubEntry?
        var bestSpecificity = -1
        for entry in entries where entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
            let specificity = entry.matchers.reduce(0) { $0 + $1.specificity }
            if specificity > bestSpecificity {
                bestSpecificity = specificity
                bestEntry = entry
            }
        }
        guard let bestEntry else { return nil }

        withLock {
            storedCalls.append(RecordedCall(
                methodIndex: method,
                name: snapshot.name,
                args: args,
                matchers: []
            ))
        }
        return bestEntry.handler
    }

    // MARK: - Stub registration

    func addStub(method: Int, matchers: [ParameterMatcher], returnValue: @escaping ([Any]) -> Any, action: (([Any]) -> Void)? = nil) {
        withLock {
            storedStubs[method, default: []].append(StubEntry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignatureLocked(method: method, matchers: matchers),
                returnValue: returnValue,
                action: action
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
