extension Stub {
    /// Waits for matching synchronous calls using `clock` rather than wall
    /// time. ``TestDoubleClock`` makes timeout tests deterministic.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        _ call: (P) throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            using: clock,
            recording: recordInvocation(call),
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits for matching async calls using `clock` rather than wall time.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            using: clock,
            recording: await recordAsyncInvocation(call, isolation: isolation),
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension ManualStub {
    /// Waits for matching synchronous manual-stub calls using `clock`.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        _ call: (T) throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            using: clock,
            recording: recordInvocation(call),
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits for matching async manual-stub calls using `clock`.
    public func verify<Result>(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await verifyCallCount(
            expectedCounts,
            within: timeout,
            using: clock,
            recording: await recordAsyncInvocation(call, isolation: isolation),
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}
