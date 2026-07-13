extension Stub {
    /// A call-count expectation used by `verify`.
    public enum CallCount: Sendable {
        /// The invocation must have occurred one or more times.
        case atLeastOnce

        /// The invocation must have occurred exactly `count` times.
        case exactly(Int)

        /// The invocation must not have occurred.
        case never
    }

    /// Verifies a method or getter invocation, including throwing requirements.
    public func verify<Result>(
        _ expectedCount: CallCount = .atLeastOnce,
        _ call: (P) throws -> Result
    ) {
        let recording = record { _ = try! call(self()) }
        verify(expectedCount, recording: recording)
    }

    /// Verifies an async method or getter invocation, including throwing requirements.
    @_disfavoredOverload
    public func verify<Result>(
        _ expectedCount: CallCount = .atLeastOnce,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async {
        let recording = await recordAsync(isolation: isolation) {
            _ = try! await call(self())
        }
        verify(expectedCount, recording: recording)
    }

    private func verify(_ expectedCount: CallCount, recording: RecordedCall) {
        if case .exactly(let count) = expectedCount {
            precondition(count >= 0, "Call count must not be negative")
        }
        let actualCount = recorder.callCount(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers
        )

        switch expectedCount {
        case .atLeastOnce:
            precondition(
                actualCount > 0,
                "'\(recording.name)': expected at least 1 call, got \(actualCount)"
            )

        case .exactly(let count):
            precondition(
                actualCount == count,
                "'\(recording.name)': expected \(count) call(s), got \(actualCount)"
            )

        case .never:
            precondition(
                actualCount == 0,
                "'\(recording.name)': expected no calls, got \(actualCount)"
            )
        }
    }
}
