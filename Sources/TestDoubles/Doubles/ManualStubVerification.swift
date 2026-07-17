extension ManualStub {
    /// Verifies a method or getter invocation, including throwing requirements.
    public func verify<Result>(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        _ call: (T) throws -> Result,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let recording = recordInvocation(call)
        verifyCallCount(
            expectedCounts,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies an invocation whose result needs a valid value while recording.
    public func verify<Result>(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        returning placeholder: Result,
        _ call: (T) throws -> Result,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let recording = recordInvocation(returning: placeholder, call)
        verifyCallCount(
            expectedCounts,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits up to `timeout` for a method or getter invocation.
    ///
    /// Eventual verification accepts only a lower-bounded count because calls
    /// can satisfy that expectation monotonically as they arrive.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        _ call: (T) throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = recordInvocation(call)
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits for an invocation whose result needs a valid value while recording.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        returning placeholder: Result,
        _ call: (T) throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = recordInvocation(returning: placeholder, call)
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies a direct property assignment.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        _ call: (inout T) throws -> Void,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let recording = recordMutation(call)
        verifyCallCount(
            expectedCounts,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits up to `timeout` for a direct property assignment.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        _ call: (inout T) throws -> Void,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = recordMutation(call)
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies that calls occurred in the listed relative order.
    public func verifyInOrder(
        _ calls: (T) throws -> Void,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let recordings = recordInvocations(calls)
        verifyInOrder(
            recordings: recordings,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies that calls, including direct property assignments, occurred in the listed relative order.
    ///
    /// Each listed invocation consumes a distinct matching recorded call.
    /// Unrelated calls may occur between matches. Use `verify` separately when
    /// call count is also significant.
    @_disfavoredOverload
    public func verifyInOrder(
        mutating calls: (inout T) throws -> Void,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let recordings = recordMutatingInvocations(calls)
        verifyInOrder(
            recordings: recordings,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies that synchronous and asynchronous calls occurred in the listed relative order.
    public func verifyInOrder(
        _ calls: (T) async throws -> Void,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recordings = await recordAsyncInvocations(calls, isolation: isolation)
        verifyInOrder(
            recordings: recordings,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies an async method or getter invocation, including throwing requirements.
    public func verify<Result>(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        verifyCallCount(
            expectedCounts,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies an async invocation whose result needs a valid value while recording.
    public func verify<Result>(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        returning placeholder: Result,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = await recordAsyncInvocation(
            returning: placeholder,
            call,
            isolation: isolation
        )
        verifyCallCount(
            expectedCounts,
            recording: recording,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits up to `timeout` for an async method or getter invocation.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            recording: recording,
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits for an async invocation whose result needs a valid value while recording.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        returning placeholder: Result,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        let recording = await recordAsyncInvocation(
            returning: placeholder,
            call,
            isolation: isolation
        )
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            recording: recording,
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}
