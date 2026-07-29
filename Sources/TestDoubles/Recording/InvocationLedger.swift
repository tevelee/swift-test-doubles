import InternalRuntimeContract
import Foundation

@_silgen_name("td_next_global_invocation_sequence")
private func nextGlobalInvocationSequence() -> UInt64

/// Process-global monotonic stamp shared by every recorder, so ordered
/// verification can compare invocation order across separate doubles, each of
/// which otherwise numbers its calls independently.
enum GlobalInvocationSequence {
    static func take() -> UInt64 {
        nextGlobalInvocationSequence()
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

/// Indicates whether the recorder answered a call itself or a spy delegated it
/// to its forwarding target.
enum InvocationOrigin: Sendable {
    case stubbed
    case forwarded
}

/// A recorded playback invocation or a capture-mode expectation.
struct RecordedCall: @unchecked Sendable {
    private final class WeakPayload {
        weak var value: (any RuntimePayload)?

        init(_ value: any RuntimePayload) {
            self.value = value
        }
    }

    private final class RuntimePayloadMaterializer {
        private weak var recorder: StubRecorder?

        init(_ recorder: StubRecorder) {
            self.recorder = recorder
        }

        func makePayload() -> (any RuntimePayload)? {
            recorder?.makeRuntimePayload() as? any RuntimePayload
        }

        func requirePayload() -> any RuntimePayload {
            guard let payload = makePayload() else {
                preconditionFailure(
                    "[TestDoubles] Recorded Self argument is no longer available because its runtime resources were released."
                )
            }
            return payload
        }
    }

    private enum ArgumentStorage {
        case strong(Any)
        case selfPayload(WeakPayload, RuntimePayloadMaterializer)
        case optionalSelfPayload(WeakPayload, RuntimePayloadMaterializer)

        init(
            _ value: Any,
            convention: RuntimeValueConvention?,
            materializer: RuntimePayloadMaterializer?
        ) {
            switch convention {
                case .selfType:
                    guard let materializer else {
                        preconditionFailure(
                            "[TestDoubles] Recorded Self argument requires a runtime payload materializer."
                        )
                    }
                    guard let payload = value as? any RuntimePayload else {
                        preconditionFailure(
                            "[TestDoubles] Runtime decoded Self argument as \(type(of: value)); expected an opaque runtime payload."
                        )
                    }
                    self = .selfPayload(WeakPayload(payload), materializer)

                case .optionalSelf:
                    guard let materializer else {
                        preconditionFailure(
                            "[TestDoubles] Recorded Optional Self argument requires a runtime payload materializer."
                        )
                    }
                    guard let optional = value as? (any RuntimePayload)? else {
                        preconditionFailure(
                            "[TestDoubles] Runtime decoded Optional Self argument as \(type(of: value)); expected an optional opaque runtime payload."
                        )
                    }
                    guard let payload = optional else {
                        self = .strong(value)
                        return
                    }
                    self = .optionalSelfPayload(WeakPayload(payload), materializer)

                case .concrete, .associatedType, .methodGenericParameter,
                    .methodGenericParameterPack, nil:
                    self = .strong(value)
            }
        }

        var value: Any {
            switch self {
                case .strong(let value): value
                case .selfPayload(let weak, let materializer):
                    weak.value ?? materializer.requirePayload()
                case .optionalSelfPayload(let weak, let materializer):
                    Optional(weak.value ?? materializer.requirePayload()) as Any
            }
        }
    }

    private enum ArgumentsStorage {
        case strong([Any])
        case selfAware([ArgumentStorage])

        var values: [Any] {
            switch self {
                case .strong(let values): values
                case .selfAware(let values): values.map(\.value)
            }
        }
    }

    let id: UInt64?
    let sequence: UInt64?
    let methodIndex: Int
    let name: String
    let origin: InvocationOrigin
    let registrationSignature: String?
    let taskPriorityRawValue: UInt8
    private let argumentsStorage: ArgumentsStorage
    let matchers: [ParameterMatcher]
    /// Empty matchers normally mean a broad fallback. An empty parameter pack
    /// is the one exception: it must match only another empty pack.
    let matchesEmptyArgumentsExactly: Bool
    let registrationLocation: StubSourceLocation?

    var args: [Any] { argumentsStorage.values }

    init(
        id: UInt64? = nil,
        sequence: UInt64? = nil,
        methodIndex: Int,
        name: String,
        origin: InvocationOrigin = .stubbed,
        registrationSignature: String? = nil,
        args: [Any],
        argumentConventions: [RuntimeValueConvention]? = nil,
        runtimePayloadRecorder: StubRecorder? = nil,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false,
        registrationLocation: StubSourceLocation? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.methodIndex = methodIndex
        self.name = name
        self.origin = origin
        self.registrationSignature = registrationSignature
        taskPriorityRawValue = Task.currentPriority.rawValue
        if let argumentConventions {
            precondition(
                argumentConventions.count == args.count,
                "[TestDoubles] Recorded argument conventions must match the decoded argument count."
            )
            let materializer = runtimePayloadRecorder.map(RuntimePayloadMaterializer.init)
            argumentsStorage = .selfAware(
                zip(args, argumentConventions).map {
                    ArgumentStorage($0, convention: $1, materializer: materializer)
                }
            )
        } else {
            argumentsStorage = .strong(args)
        }
        self.matchers = matchers
        self.matchesEmptyArgumentsExactly = matchesEmptyArgumentsExactly
        self.registrationLocation = registrationLocation
    }

    private init(
        id: UInt64?,
        sequence: UInt64?,
        methodIndex: Int,
        name: String,
        origin: InvocationOrigin,
        registrationSignature: String?,
        taskPriorityRawValue: UInt8,
        argumentsStorage: ArgumentsStorage,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool,
        registrationLocation: StubSourceLocation?
    ) {
        self.id = id
        self.sequence = sequence
        self.methodIndex = methodIndex
        self.name = name
        self.origin = origin
        self.registrationSignature = registrationSignature
        self.taskPriorityRawValue = taskPriorityRawValue
        self.argumentsStorage = argumentsStorage
        self.matchers = matchers
        self.matchesEmptyArgumentsExactly = matchesEmptyArgumentsExactly
        self.registrationLocation = registrationLocation
    }

    /// Returns a copy tagged with the `when` call's source location.
    func taggingRegistrationLocation(_ location: StubSourceLocation?) -> RecordedCall {
        RecordedCall(
            id: id,
            sequence: sequence,
            methodIndex: methodIndex,
            name: name,
            origin: origin,
            registrationSignature: registrationSignature,
            taskPriorityRawValue: taskPriorityRawValue,
            argumentsStorage: argumentsStorage,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
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

    var latestRecordedCallID: UInt64? { calls.last?.id }

    mutating func append(
        method: Int,
        name: String,
        origin: InvocationOrigin = .stubbed,
        registrationSignature: String? = nil,
        args: [Any],
        argumentConventions: [RuntimeValueConvention]? = nil,
        runtimePayloadRecorder: StubRecorder? = nil
    ) -> [InvocationLedgerWaiter] {
        let callID = nextRecordedCallID
        nextRecordedCallID &+= 1
        calls.append(
            RecordedCall(
                id: callID,
                sequence: GlobalInvocationSequence.take(),
                methodIndex: method,
                name: name,
                origin: origin,
                registrationSignature: registrationSignature,
                args: args,
                argumentConventions: argumentConventions,
                runtimePayloadRecorder: runtimePayloadRecorder,
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
