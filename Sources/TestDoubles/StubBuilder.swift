/// Configures the result of a stubbed method or property.
public struct StubBuilder<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Returns `value` whenever the recorded invocation matches.
    public func returns(_ value: Result) {
        recorder.addStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            returnValue: { _ in value }
        )
    }

    /// Handles a matching invocation with typed arguments.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. A handler that throws at runtime requires a throwing
    ///   requirement.
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) throws -> Result
    ) {
        recorder.addStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            returnValue: { arguments in
                try invokeTypedHandler(handler, with: arguments, method: recording.name)
            }
        )
    }

    /// Handles a matching async invocation with typed arguments.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. The requirement must be async, and a handler that throws at
    ///   runtime requires a throwing requirement.
    @_disfavoredOverload
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Result
    ) {
        recorder.addAsyncStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers
        ) { arguments in
            try await invokeTypedHandler(handler, with: arguments, method: recording.name)
        }
    }
}
