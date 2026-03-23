/// Records method calls and returns stubbed values.
/// Supports three modes: normal (dispatch to stubs), recording (capture calls),
/// and verifying (check call log).
public class StubRecorder: @unchecked Sendable {
    public init() {}

    public enum Mode {
        case normal
        case recording
        case verifying
    }

    public var mode: Mode = .normal

    // Stub storage: method index → [(matchers, returnValue, action)]
    var stubs: [Int: [StubEntry]] = [:]
    var names: [Int: String] = [:]

    // Call log
    public private(set) var calls: [RecordedCall] = []

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

    public func setName(_ name: String, for index: Int) {
        names[index] = name
    }

    // MARK: - Dispatch (called by witness table thunks)

    public func dispatch(method: Int, args: [Any]) -> Any {
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
            for entry in entries {
                if entry.matchers.isEmpty || matchArgs(args, against: entry.matchers) {
                    calls.append(RecordedCall(methodIndex: method, name: name, args: args, matchers: []))
                    entry.action?(args)
                    return entry.returnValue(args)
                }
            }
            fatalError("No matching stub for '\(name)' with args \(args)")
        }
    }

    // MARK: - Stub registration

    func addStub(method: Int, matchers: [ParameterMatcher], returnValue: @escaping ([Any]) -> Any, action: (([Any]) -> Void)? = nil) {
        stubs[method, default: []].append(StubEntry(matchers: matchers, returnValue: returnValue, action: action))
    }

    // MARK: - Verification queries

    public func callCount(method: Int, matchers: [ParameterMatcher] = []) -> Int {
        calls.filter { call in
            call.methodIndex == method && (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }.count
    }

    public func reset() { calls.removeAll() }

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

// MARK: - Parameter Matchers

public protocol ParameterMatcher {
    func matches(value: Any) -> Bool
}

struct AnyMatcher: ParameterMatcher {
    func matches(value: Any) -> Bool { true }
}

struct EqualMatcher<V: Equatable>: ParameterMatcher {
    let expected: V
    func matches(value: Any) -> Bool { (value as? V) == expected }
}

struct PredicateMatcher<V>: ParameterMatcher {
    let predicate: (V) -> Bool
    func matches(value: Any) -> Bool {
        guard let v = value as? V else { return false }
        return predicate(v)
    }
}

struct DescriptionMatcher: ParameterMatcher {
    let desc: String
    init(value: Any) { self.desc = String(describing: value) }
    func matches(value: Any) -> Bool { String(describing: value) == desc }
}
