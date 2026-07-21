import Foundation

/// Process-global monotonic stamp shared by every recorder, so ordered
/// verification can compare invocation order across separate doubles, each of
/// which otherwise numbers its calls independently.
enum GlobalInvocationSequence {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: UInt64 = 0

    static func take() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        current &+= 1
        return current
    }
}

/// The source location of a `when` call, so a diagnostic about the
/// registration (such as an unreachable stub) can point at the test.
struct StubSourceLocation: Sendable {
    let fileID: StaticString
    let filePath: StaticString
    let line: UInt
    let column: UInt
}

/// A recorded playback invocation or a capture-mode expectation.
struct RecordedCall: @unchecked Sendable {
    let id: UInt64?
    let sequence: UInt64?
    let methodIndex: Int
    let name: String
    let args: [Any]
    let matchers: [ParameterMatcher]
    let registrationLocation: StubSourceLocation?

    init(
        id: UInt64? = nil,
        sequence: UInt64? = nil,
        methodIndex: Int,
        name: String,
        args: [Any],
        matchers: [ParameterMatcher],
        registrationLocation: StubSourceLocation? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.methodIndex = methodIndex
        self.name = name
        self.args = args
        self.matchers = matchers
        self.registrationLocation = registrationLocation
    }

    /// Returns a copy tagged with the `when` call's source location.
    func taggingRegistrationLocation(_ location: StubSourceLocation?) -> RecordedCall {
        RecordedCall(
            id: id,
            sequence: sequence,
            methodIndex: methodIndex,
            name: name,
            args: args,
            matchers: matchers,
            registrationLocation: location
        )
    }

    var resolvedMatchers: [ParameterMatcher] {
        matchers.isEmpty
            ? args.map { DescriptionMatcher(value: $0) }
            : matchers
    }
}

enum InvocationLedgerWaitOutcome: Equatable, Sendable {
    case changed
    case timedOut
    case cancelled
}

final class InvocationLedgerWaiter: @unchecked Sendable {
    private let resolve: @Sendable (InvocationLedgerWaitOutcome) -> Void
    var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<InvocationLedgerWaitOutcome, Never>) {
        self.resolve = { outcome in
            continuation.resume(returning: outcome)
        }
    }

    init(resolve: @escaping @Sendable (InvocationLedgerWaitOutcome) -> Void) {
        self.resolve = resolve
    }

    func resume(returning outcome: InvocationLedgerWaitOutcome) {
        resolve(outcome)
    }
}

struct InvocationLedgerGeneration: Equatable, Sendable {
    let method: Int
    let methodGeneration: UInt64
    let clearGeneration: UInt64
}

/// Lock-agnostic call and waiter state owned and synchronized by
/// ``StubRecorder``.
struct InvocationLedger {
    private var calls: [RecordedCall] = []
    private var nextRecordedCallID: UInt64 = 0
    private var verifiedCallIDs: Set<UInt64> = []
    private var methodGenerations: [Int: UInt64] = [:]
    private var clearGeneration: UInt64 = 0
    private var nextCallWaiterID: UInt64 = 0
    private var callWaitersByMethod: [Int: [UInt64: InvocationLedgerWaiter]] = [:]
    private var waiterMethods: [UInt64: Int] = [:]

    func snapshot(
        for method: Int
    ) -> (calls: [RecordedCall], generation: InvocationLedgerGeneration) {
        (calls, generation(for: method))
    }

    var allCalls: [RecordedCall] { calls }

    mutating func append(
        method: Int,
        name: String,
        args: [Any]
    ) -> [InvocationLedgerWaiter] {
        let callID = nextRecordedCallID
        nextRecordedCallID &+= 1
        calls.append(
            RecordedCall(
                id: callID,
                sequence: GlobalInvocationSequence.take(),
                methodIndex: method,
                name: name,
                args: args,
                matchers: []
            ))
        methodGenerations[method, default: 0] &+= 1
        return takeWaiters(for: method)
    }

    mutating func clear() -> [InvocationLedgerWaiter] {
        calls.removeAll(keepingCapacity: true)
        verifiedCallIDs.removeAll(keepingCapacity: true)
        clearGeneration &+= 1
        return takeAllWaiters()
    }

    mutating func markVerified(_ recordedCalls: [RecordedCall]) {
        verifiedCallIDs.formUnion(recordedCalls.compactMap(\.id))
    }

    func unverifiedCalls() -> [RecordedCall] {
        calls.filter { call in
            guard let id = call.id else { return true }
            return verifiedCallIDs.contains(id) == false
        }
    }

    mutating func allocateWaiterID() -> UInt64 {
        defer { nextCallWaiterID &+= 1 }
        return nextCallWaiterID
    }

    mutating func register(
        _ waiter: InvocationLedgerWaiter,
        id: UInt64,
        after generation: InvocationLedgerGeneration,
        isCancelled: Bool
    ) -> InvocationLedgerWaitOutcome? {
        if isCancelled {
            return .cancelled
        }
        if self.generation(for: generation.method) != generation {
            return .changed
        }
        callWaitersByMethod[generation.method, default: [:]][id] = waiter
        waiterMethods[id] = generation.method
        return nil
    }

    mutating func attachTimeoutTask(
        _ timeoutTask: Task<Void, Never>,
        to waiterID: UInt64
    ) -> Bool {
        guard let method = waiterMethods[waiterID],
            let waiter = callWaitersByMethod[method]?[waiterID]
        else {
            return false
        }
        waiter.timeoutTask = timeoutTask
        return true
    }

    mutating func removeWaiter(id: UInt64) -> InvocationLedgerWaiter? {
        guard let method = waiterMethods.removeValue(forKey: id),
            let waiter = callWaitersByMethod[method]?.removeValue(forKey: id)
        else {
            return nil
        }
        if callWaitersByMethod[method]?.isEmpty == true {
            callWaitersByMethod.removeValue(forKey: method)
        }
        return waiter
    }

    func pendingWaiterCount(for method: Int) -> Int {
        callWaitersByMethod[method]?.count ?? 0
    }

    private func generation(for method: Int) -> InvocationLedgerGeneration {
        InvocationLedgerGeneration(
            method: method,
            methodGeneration: methodGenerations[method, default: 0],
            clearGeneration: clearGeneration
        )
    }

    private mutating func takeWaiters(for method: Int) -> [InvocationLedgerWaiter] {
        guard let waiters = callWaitersByMethod.removeValue(forKey: method) else {
            return []
        }
        for waiterID in waiters.keys {
            waiterMethods.removeValue(forKey: waiterID)
        }
        return Array(waiters.values)
    }

    private mutating func takeAllWaiters() -> [InvocationLedgerWaiter] {
        let waiters = callWaitersByMethod.values.flatMap(\.values)
        callWaitersByMethod.removeAll(keepingCapacity: true)
        waiterMethods.removeAll(keepingCapacity: true)
        return waiters
    }
}
