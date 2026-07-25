import TestDoublesRuntime

/// The transitional public-layer endpoint for compiler-typed witness
/// adapters. Keeping the recorder here prevents the runtime target from
/// depending on TestDoubles recording semantics.
final class StubRecorderInvocationEndpoint: RuntimeInvocationEndpoint,
    @unchecked Sendable
{
    private let recorder: StubRecorder

    init(recorder: StubRecorder) {
        self.recorder = recorder
    }

    func dispatchTyped<Result>(
        method: MethodDescriptor,
        args: [Any],
        as resultType: Result.Type
    ) throws -> Result {
        try recorder.dispatchTyped(method: method, args: args, as: resultType)
    }
}
