#if RUNTIME_STUB
/// Records method calls and returns stubbed values.
/// Supports three modes: normal (dispatch to stubs), recording (capture calls),
/// and verifying (check call log).
class StubRecorder: @unchecked Sendable {
    init() {}

    enum Mode {
        case normal
        case recording
        case verifying
    }

    var mode: Mode = .normal

    // Stub storage: method index → [(matchers, returnValue, action)]
    var stubs: [Int: [StubEntry]] = [:]
    var names: [Int: String] = [:]

    // ARC flags: tracks which method slots return reference types
    var refReturnFlags: [Int: Bool] = [:]

    /// Returns true if the method at the given index returns a reference type
    /// (needs +1 retain when returned as raw bits through ABI-class thunks).
    func isRefReturn(_ methodIndex: Int) -> Bool {
        refReturnFlags[methodIndex] ?? false
    }

    // Call log
    var calls: [RecordedCall] = []

    // Last recording (set during recording mode)
    var lastRecording: RecordedCall?

    // Active matchers (set by any()/equal()/match() before a call)
    var activeMatchers: [ParameterMatcher] = []

    struct StubEntry {
        let matchers: [ParameterMatcher]
        let returnValue: ([Any]) -> Any
        let action: (([Any]) -> Void)?
    }

    // MARK: - Method name registration

    func setName(_ name: String, for index: Int) {
        names[index] = name
    }

    // MARK: - Dispatch (called by witness table thunks)

    func dispatch(method: Int, args: [Any]) -> Any {
        let name = names[method] ?? "method_\(method)"

        switch mode {
        case .recording:
            // Capture the matchers that were set before this call
            let matchers = activeMatchers
            activeMatchers = []
            lastRecording = RecordedCall(methodIndex: method, name: name, args: args, matchers: matchers)
            return zeroValue // thunk handles the actual return type

        case .verifying:
            let matchers = activeMatchers
            activeMatchers = []
            lastRecording = RecordedCall(methodIndex: method, name: name, args: args, matchers: matchers)
            return zeroValue

        case .normal:
            guard let entries = stubs[method] else {
                fatalError("No stub configured for '\(name)' (index \(method))")
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
                fatalError("No matching stub for '\(name)' with args \(args)")
            }
            calls.append(RecordedCall(methodIndex: method, name: name, args: args, matchers: []))
            entry.action?(args)
            return entry.returnValue(args)
        }
    }

    // MARK: - Throwing stubs

    var throwingStubs: [Int: [ThrowingStubEntry]] = [:]

    struct ThrowingStubEntry {
        let matchers: [ParameterMatcher]
        let handler: ([Any]) throws -> Any
    }

    /// Register a stub that throws.
    func addThrowingStub(method: Int, matchers: [ParameterMatcher], handler: @escaping ([Any]) throws -> Any) {
        throwingStubs[method, default: []].append(ThrowingStubEntry(matchers: matchers, handler: handler))
    }

    /// Dispatch a throwing call. Returns nil if no throwing stub is registered.
    func dispatchThrowing(method: Int, args: [Any]) -> Result<Any, any Error>? {
        guard let entries = throwingStubs[method] else { return nil }
        for entry in entries {
            if entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
                let name = names[method] ?? "method_\(method)"
                calls.append(RecordedCall(methodIndex: method, name: name, args: args, matchers: []))
                do {
                    return .success(try entry.handler(args))
                } catch {
                    return .failure(error)
                }
            }
        }
        return nil
    }

    // MARK: - Stub registration

    func addStub(method: Int, matchers: [ParameterMatcher], returnValue: @escaping ([Any]) -> Any, action: (([Any]) -> Void)? = nil) {
        stubs[method, default: []].append(StubEntry(matchers: matchers, returnValue: returnValue, action: action))
    }

    // MARK: - Verification queries

    func callCount(method: Int, matchers: [ParameterMatcher] = []) -> Int {
        calls.filter { call in
            call.methodIndex == method && (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }.count
    }

    func reset() {
        calls.removeAll()
    }

    // MARK: - Matching

    private func matchArgs(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }

    // Sentinel value for recording/verifying mode returns
    private var zeroValue: Any { 0 as Int }
}

// MARK: - RecordedCall

public struct RecordedCall {
    public let methodIndex: Int
    public let name: String
    public let args: [Any]
    var matchers: [ParameterMatcher]
}
#endif
