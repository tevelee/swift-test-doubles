/// A runtime-decoded invocation routed to the public semantic endpoint.
/// `slot` is a dense dispatch identity, not a witness-table index -- the
/// endpoint resolves it against its own method catalog.
package struct RuntimeInvocationRequest: @unchecked Sendable {
    package let slot: Int
    package let arguments: [Any]

    package init(slot: Int, arguments: [Any]) {
        self.slot = slot
        self.arguments = arguments
    }
}

/// The recorder slots paired by a `_modify` accessor.
package struct RuntimeModifyDispatch: Sendable {
    package let getterSlot: Int
    package let setterSlot: Int

    package init(getterSlot: Int, setterSlot: Int) {
        self.getterSlot = getterSlot
        self.setterSlot = setterSlot
    }
}

/// Encodes a generated runtime payload as a dependent result.
package enum RuntimeDependentResult: Sendable {
    case payload
    case nilPayload
}

/// A temporary result selected while a requirement is being recorded.
package enum RuntimeRecordingResult: @unchecked Sendable {
    case payload
    case nilPayload
    case value(Any)
    case synthesize
}

/// An opaque generated-value payload, used only to preserve dynamic-`Self`
/// identities during recording. Storage and owned resources stay
/// implementation details of the ABI runtime.
package protocol RuntimePayload: AnyObject {}

/// The endpoint mode used to select borrowed or consuming argument decoding.
package enum RuntimeInvocationMode: Sendable {
    case normal
    case capturing
}

/// A behavior selected by the public semantic layer after recording the call.
package enum RuntimeDispatchBehavior: @unchecked Sendable {
    case fixed(Result<Any, any Error>)
    case immediate(([Any]) throws -> Any)
    case suspending(([Any]) async throws -> Any)
}

/// Recorder-local identity for one invocation whose forwarding completion is
/// reported by the ABI runtime.
package struct RuntimeInvocationToken: Sendable {
    package let id: UInt64

    package init(id: UInt64) {
        self.id = id
    }
}

/// The public layer's synchronous dispatch selection.
package enum RuntimePreparedDispatch: @unchecked Sendable {
    case recording
    case behavior(RuntimeDispatchBehavior)
    case forwarding(RuntimeInvocationToken)
}

/// The public layer's asynchronous dispatch selection.
package enum RuntimeAsyncDispatch: @unchecked Sendable {
    case recording
    case immediate(Result<Any, any Error>)
    case suspending(([Any]) async throws -> Any)
    case forwarding(RuntimeInvocationToken)
}

/// Semantic policy invoked by the ABI runtime. Transports only dispatch
/// slots and boxed Swift values; metadata, ABI plans, and frame storage stay
/// implementation details of `TestDoublesRuntime`.
package protocol RuntimeInvocationEndpoint: AnyObject, Sendable {
    func prepareDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimePreparedDispatch

    func prepareAsyncDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimeAsyncDispatch

    /// Marks an invocation delegated to a forwarding target as complete.
    ///
    /// The ABI transport owns the target call and therefore is the only layer
    /// that can report its completion boundary reliably.
    func completeForwardedInvocation(_ token: RuntimeInvocationToken)

    var invocationMode: RuntimeInvocationMode { get }

    func modifyDispatch(
        forGetterSlot getterSlot: Int
    ) -> RuntimeModifyDispatch?

    func rejectInvocation(at slot: Int) -> Never

    func methodName(at slot: Int) -> String

    func recordingAccessorResult(at slot: Int) -> Any

    func dispatchTyped<Result>(
        _ request: RuntimeInvocationRequest,
        as resultType: Result.Type
    ) throws -> Result

    /// Receives the runtime resource owner after witness publication and
    /// before a fabricated existential commits its witness identities.
    ///
    /// The contract uses `AnyObject` so the public semantic layer can retain
    /// the owner without importing ABI resource types.
    func runtimeResourcesDidPublish(_ resources: AnyObject)

    func runtimePayload() -> AnyObject?

    func dependentResult(
        for result: Any,
        at slot: Int
    ) -> RuntimeDependentResult

    func recordingResult(at slot: Int) -> RuntimeRecordingResult
}
