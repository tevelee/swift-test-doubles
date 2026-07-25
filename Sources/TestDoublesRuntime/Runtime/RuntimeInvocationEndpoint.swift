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

/// The TestDoubles-owned semantic endpoint used by a compiler-typed witness
/// adapter. The runtime retains and transports this object opaquely; only the
/// public layer decides how a decoded typed call is recorded or dispatched.
package protocol RuntimeInvocationEndpoint: AnyObject, Sendable {
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
