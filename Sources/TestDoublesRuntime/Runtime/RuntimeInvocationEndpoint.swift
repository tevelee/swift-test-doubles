/// The TestDoubles-owned semantic endpoint used by runtime witness adapters.
///
/// The runtime retains this object opaquely and asks it only for semantic
/// decisions. It remains responsible for decoding arguments and encoding the
/// resulting values into ABI call frames.
package enum RuntimeDependentResult: Sendable {
    /// Encode the generated runtime payload as a dynamic `Self` result.
    case payload
    /// Encode a `nil` dynamic `Self` result.
    case nilPayload
}

/// A semantic result selected while a requirement is being recorded.
package enum RuntimeRecordingResult: @unchecked Sendable {
    /// Encode the generated runtime payload as the temporary result.
    case payload
    /// Encode `nil` as the temporary result.
    case nilPayload
    /// Encode this explicitly supplied temporary value.
    case value(Any)
    /// Synthesize an ABI-safe fallback value from runtime metadata.
    case synthesize
}

/// The endpoint's current semantic mode. The runtime uses this only to select
/// the ABI ownership plan for a forwarded call; capture policy stays in the
/// public layer.
package enum RuntimeInvocationMode: Sendable {
    case normal
    case capturing
}

/// A behavior selected by the public semantic layer after it has atomically
/// recorded the invocation and reserved any queued result. The runtime owns
/// invocation and frame transport; the endpoint owns matching and diagnostics.
package enum RuntimeDispatchBehavior: @unchecked Sendable {
    case fixed(Result<Any, any Error>)
    case immediate(([Any]) throws -> Any)
    case suspending(([Any]) async throws -> Any)
}

/// The result of selecting a synchronous invocation policy.
package enum RuntimePreparedDispatch: @unchecked Sendable {
    case recording
    case behavior(RuntimeDispatchBehavior)
    case forwarding
}

/// The result of selecting an asynchronous invocation policy.
package enum RuntimeAsyncDispatch: @unchecked Sendable {
    case recording
    case immediate(Result<Any, any Error>)
    case suspending(([Any]) async throws -> Any)
    case forwarding
}

/// The TestDoubles-owned semantic endpoint used by a compiler-typed witness
/// adapter. The runtime retains and transports this object opaquely; only the
/// public layer decides how a decoded typed call is recorded or dispatched.
package protocol RuntimeInvocationEndpoint: AnyObject, Sendable {
    /// Records and selects synchronous behavior. The endpoint must not invoke
    /// user behavior while holding its own synchronization primitive.
    func prepareDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> RuntimePreparedDispatch

    /// Records and selects async behavior, preserving a suspending handler as
    /// an opaque runtime-neutral closure.
    func prepareAsyncDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> RuntimeAsyncDispatch

    /// Provides the endpoint mode for the runtime's borrowed-vs-consuming
    /// decode decision when a forwarding target exists.
    var invocationMode: RuntimeInvocationMode { get }

    /// Returns the paired getter/setter descriptor for a `_modify` entry.
    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: MethodDescriptor, setter: MethodDescriptor)?

    /// Rejects a call which has no semantic behavior, such as a dummy value.
    func rejectInvocation(at slot: Int) -> Never

    /// Supplies the typed temporary value required by a recording read
    /// accessor. Its diagnostic policy belongs to the public endpoint.
    func recordingAccessorResult(for method: MethodDescriptor) -> Any

    func dispatchTyped<Result>(
        method: MethodDescriptor,
        args: [Any],
        as resultType: Result.Type
    ) throws -> Result

    /// Supplies the opaque generated payload when a requirement returns a
    /// runtime-dependent `Self` value.
    func runtimePayload() -> AnyObject?

    /// Interprets the public-layer sentinel returned by an initializer or a
    /// dynamic-`Self` handler. This keeps public builder types out of the
    /// runtime module.
    func dependentResult(
        for result: Any,
        method: MethodDescriptor
    ) -> RuntimeDependentResult

    /// Chooses recording-only result policy. The runtime performs all raw
    /// storage initialization and frame encoding after this decision.
    func recordingResult(
        for method: MethodDescriptor,
        args: [Any]
    ) -> RuntimeRecordingResult
}
