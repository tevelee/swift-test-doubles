import Foundation

struct ModifyDispatchDescriptor: Sendable {
    let getterDispatchIndex: Int
    let setterDispatchIndex: Int
}

/// Records method calls and returns stubbed values.
/// Uses normal dispatch and task-local capture sessions shared by stubbing and
/// verification.
final class StubRecorder: @unchecked Sendable {
    /// Mutable policy is grouped so extensions cannot accidentally lock only
    /// one registry during an operation that must commit atomically.
    struct LockedPolicyState {
        var methodCatalog: ManualMethodCatalog
        var behaviorRegistry = StubBehaviorRegistry()
        var invocationLedger = InvocationLedger()
    }

    private var policy: LockedPolicyState
    private weak var runtimeResourceOwner: AnyObject?
    let allowsForwardingFallback: Bool

    /// The recorder is the only owner of the lock protecting its policy state.
    /// Matcher predicates, handlers, and waiter resumes always run after the
    /// lock is released. Captor commits share the invocation commit so capture,
    /// recording, and queued-result reservation have one ordering point.
    private let lock = NSLock()

    init(
        methods: [MethodDescriptor],
        modifyDispatchDescriptors: [Int: ModifyDispatchDescriptor] = [:],
        allowsForwardingFallback: Bool = false
    ) {
        policy = LockedPolicyState(
            methodCatalog: ManualMethodCatalog(
                methods: methods,
                modifyDispatchDescriptors: modifyDispatchDescriptors
            )
        )
        self.allowsForwardingFallback = allowsForwardingFallback
    }

    enum Mode {
        case normal
        case capturing
    }

    enum EventualCallCountResult {
        case satisfied
        case timedOut(actualCount: Int)
        case cancelled
    }

    enum AsyncDispatch {
        case placeholder
        case immediate(Result<Any, any Error>)
        case suspending(([Any]) async throws -> Any)
        case forwarding
    }

    enum PreparedDispatch {
        case placeholder
        case behavior(StubEntry.Behavior)
        case forwarding
    }

    var mode: Mode {
        StubCaptureCoordinator.isCapturing(self) ? .capturing : .normal
    }

    // MARK: - Method catalog and runtime resources

    func runtimeMethod(for index: Int) -> MethodDescriptor? {
        // Locked because a manual stub's first forwarding of a requirement
        // appends to the catalog while other invocations may be reading.
        withLockedPolicy { $0.methodCatalog.method(at: index) }
    }

    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: MethodDescriptor, setter: MethodDescriptor)? {
        withLockedPolicy {
            $0.methodCatalog.modifyDispatchMethods(forGetterIndex: getterIndex)
        }
    }

    func returnValueMatchesRuntimeType(_ value: Any, for methodIndex: Int) -> Bool {
        guard let method = runtimeMethod(for: methodIndex) else { return false }
        guard case .associatedType = method.result.dependency else { return true }

        func matches<Expected>(_ type: Expected.Type) -> Bool {
            value is Expected
        }
        return _openExistential(method.returnType, do: matches)
    }

    func requireReturnValueMatchesRuntimeType(
        _ value: Any,
        for methodIndex: Int
    ) {
        guard returnValueMatchesRuntimeType(value, for: methodIndex) else {
            let expected =
                runtimeMethod(for: methodIndex).map {
                    runtimeTypeName($0.returnType)
                } ?? "<missing method>"
            preconditionFailure(
                "[TestDoubles] Associated result must be \(expected), got \(type(of: value))."
            )
        }
    }

    func requireThrownErrorMatchesRuntimeType(
        _ error: any Error,
        for method: MethodDescriptor
    ) {
        guard let expectedType = method.typedErrorType else {
            return
        }

        func matches<Expected>(_ type: Expected.Type) -> Bool {
            error is Expected
        }
        guard _openExistential(expectedType, do: matches) else {
            fatalError(
                "[TestDoubles] Typed error must be \(expectedType), got \(type(of: error))."
            )
        }
    }

    func attachRuntimeResources(_ resources: AnyObject) {
        withLockedPolicy { _ in
            precondition(
                runtimeResourceOwner == nil,
                "[TestDoubles] Runtime resources may only be attached once."
            )
            runtimeResourceOwner = resources
        }
    }

    func makeRuntimePayload() -> StubPayload? {
        withLockedPolicy { _ in runtimeResourceOwner }
            .map(StubPayload.init(resources:))
    }

    // MARK: - Manual stub method interning

    /// Interns a manually-dispatched method, getter, or setter by identity.
    /// The visible signature remains the diagnostic name, while result type
    /// and effects keep legal Swift overloads in distinct recorder slots.
    func internManualMethod(
        signature: String,
        kind: StubRequirementKind,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> MethodDescriptor {
        internManualMethod(
            route: .implicit(signature),
            kind: kind,
            returnType: returnType,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
    }

    /// Interns a manually-dispatched requirement using either its legacy
    /// printed signature or a typed route discriminator.
    func internManualMethod(
        route: ManualMethodRouteIdentity,
        kind: StubRequirementKind,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> MethodDescriptor {
        withLockedPolicy {
            $0.methodCatalog.internManualMethod(
                route: route,
                kind: kind,
                returnType: returnType,
                isAsync: isAsync,
                isThrowing: isThrowing
            )
        }
    }

    // MARK: - Capture lifecycle

    func captureCalls(_ operation: () -> Void) -> [RecordedCall] {
        StubCaptureCoordinator.capture(recorder: self, operation)
    }

    func captureCalls(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async -> Void
    ) async -> [RecordedCall] {
        await StubCaptureCoordinator.capture(
            recorder: self,
            isolation: isolation,
            operation
        )
    }

    @discardableResult
    func withLockedPolicy<Result, Failure: Error>(
        _ operation: (inout LockedPolicyState) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation(&policy)
    }

    func resumeWaiters(
        _ waiters: [InvocationLedgerWaiter],
        returning outcome: InvocationLedgerWaitOutcome
    ) {
        for waiter in waiters {
            waiter.timeoutTask?.cancel()
            waiter.resume(returning: outcome)
        }
    }
}
