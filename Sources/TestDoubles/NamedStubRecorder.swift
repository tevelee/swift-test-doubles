#if MANUAL_STUB
/// String-keyed stub recorder backing ``Stub``.
/// Mirrors ``StubRecorder`` but identifies methods by name instead of witness-table index,
/// so no thunks, reflection, or runtime compilation are required.
class NamedStubRecorder: @unchecked Sendable {

    enum Mode { case normal, recording, verifying }
    var mode: Mode = .normal

    struct Entry {
        let matchers: [ParameterMatcher]
        let returnValue: ([Any]) -> Any
        let action: (([Any]) -> Void)?
    }

    struct ThrowingEntry {
        let matchers: [ParameterMatcher]
        let handler: ([Any]) throws -> Any
    }

    var stubs: [String: [Entry]] = [:]
    var throwingStubs: [String: [ThrowingEntry]] = [:]
    var calls: [NamedRecordedCall] = []
    var lastRecording: NamedRecordedCall?

    // MARK: - Dispatch

    func dispatch<R>(method: String, args: [Any]) -> R {
        switch mode {
        case .recording, .verifying:
            lastRecording = NamedRecordedCall(methodName: method, args: args, matchers: [])
            return zeroValue(R.self)

        case .normal:
            guard let entries = stubs[method] else {
                fatalError("[TestDoubles] No stub configured for '\(method)'")
            }
            var best: Entry?
            var bestSpecificity = -1
            for entry in entries {
                if entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
                    let s = entry.matchers.reduce(0) { $0 + $1.specificity }
                    if s > bestSpecificity { bestSpecificity = s; best = entry }
                }
            }
            guard let entry = best else {
                fatalError("[TestDoubles] No matching stub for '\(method)' with args \(args)")
            }
            calls.append(NamedRecordedCall(methodName: method, args: args, matchers: []))
            entry.action?(args)
            let result = entry.returnValue(args)
            if R.self == Void.self { return unsafeBitCast((), to: R.self) }
            // swiftlint:disable:next force_cast
            return result as! R
        }
    }

    func dispatchThrowing<R>(method: String, args: [Any]) throws -> R {
        guard mode == .normal else {
            lastRecording = NamedRecordedCall(methodName: method, args: args, matchers: [])
            return zeroValue(R.self)
        }
        if let entries = throwingStubs[method] {
            for entry in entries {
                if entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
                    calls.append(NamedRecordedCall(methodName: method, args: args, matchers: []))
                    let result = try entry.handler(args)
                    if R.self == Void.self { return unsafeBitCast((), to: R.self) }
                    // swiftlint:disable:next force_cast
                    return result as! R
                }
            }
        }
        return dispatch(method: method, args: args)
    }

    func dispatchAsync<R>(method: String, args: [Any]) async -> R {
        dispatch(method: method, args: args)
    }

    // MARK: - Registration

    func addStub<R>(
        method: String,
        matchers: [ParameterMatcher],
        returnValue: @escaping ([Any]) -> R,
        action: (([Any]) -> Void)? = nil
    ) {
        stubs[method, default: []].append(Entry(
            matchers: matchers,
            returnValue: { returnValue($0) },
            action: action
        ))
    }

    func addThrowingStub(
        method: String,
        matchers: [ParameterMatcher],
        handler: @escaping ([Any]) throws -> Any
    ) {
        throwingStubs[method, default: []].append(ThrowingEntry(matchers: matchers, handler: handler))
    }

    // MARK: - Verification

    func callCount(method: String, matchers: [ParameterMatcher] = []) -> Int {
        calls.filter { call in
            call.methodName == method &&
            (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }.count
    }

    func reset() { calls.removeAll() }

    // MARK: - Helpers

    private func matchArgs(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }
}

// MARK: - NamedRecordedCall

struct NamedRecordedCall {
    let methodName: String
    let args: [Any]
    var matchers: [ParameterMatcher]
}
#endif
