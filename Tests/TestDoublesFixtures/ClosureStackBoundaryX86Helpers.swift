#if arch(x86_64)
    public func externalStackSyncClosure(offset: Int) -> ExternalStackSyncClosure {
        { $0 + $1 + $2 + $3 + $4 + $5 + $6 + offset }
    }

    public func externalInvokeStackSync(_ closure: ExternalStackSyncClosure) -> Int {
        closure(1, 2, 3, 4, 5, 6, 7)
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    public func externalStackTypedClosure(
        offset: Int,
        failure: ExternalLargeClosureError
    ) -> ExternalStackTypedClosure {
        {
            (
                first: Int,
                second: Int,
                third: Int,
                fourth: Int,
                fifth: Int,
                sixth: Int
            ) throws(ExternalLargeClosureError) -> Int in
            guard first != 0 else { throw failure }
            return first + second + third + fourth + fifth + sixth + offset
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    public func externalInvokeStackTyped(
        _ closure: ExternalStackTypedClosure,
        first: Int
    ) throws(ExternalLargeClosureError) -> Int {
        try closure(first, 2, 3, 4, 5, 6)
    }

    public func externalStackAsyncClosure(offset: Int) -> ExternalStackAsyncClosure {
        { first, second, third, fourth, fifth, sixth in
            await Task.yield()
            return ExternalNullaryLargeResult(
                first: first + second + third + fourth + fifth + sixth + offset,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
    }

    public func externalInvokeStackAsync(
        _ closure: ExternalStackAsyncClosure
    ) async -> ExternalNullaryLargeResult {
        await closure(1, 2, 3, 4, 5, 6)
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    public func externalStackAsyncTypedClosure(
        offset: Int,
        failure: ExternalLargeClosureError
    ) -> ExternalStackAsyncTypedClosure {
        {
            (
                first: Int,
                second: Int,
                third: Int,
                fourth: Int,
                fifth: Int
            ) async throws(ExternalLargeClosureError) -> ExternalNullaryLargeResult in
            await Task.yield()
            guard first != 0 else { throw failure }
            return ExternalNullaryLargeResult(
                first: first + second + third + fourth + fifth + offset,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    public func externalInvokeStackAsyncTyped(
        _ closure: ExternalStackAsyncTypedClosure,
        first: Int
    ) async throws(ExternalLargeClosureError) -> ExternalNullaryLargeResult {
        try await closure(first, 2, 3, 4, 5)
    }

    public func externalDirectStackInputClosure(
        offset: Int
    ) -> ExternalDirectStackInputClosure {
        { pair, second, third, fourth, fifth, sixth in
            pair.first + pair.second + second + third + fourth + fifth + sixth + offset
        }
    }

    public func externalInvokeDirectStackInput(
        _ closure: ExternalDirectStackInputClosure
    ) -> Int {
        closure(.init(first: 1, second: 2), 3, 4, 5, 6, 7)
    }

    public func externalDirectAsyncStackInputClosure(
        offset: Int
    ) -> ExternalDirectAsyncStackInputClosure {
        { first, second, third, fourth, fifth, sixth in
            await Task.yield()
            return ExternalNullaryLargeResult(
                first: first + second + third + fourth + fifth + sixth + offset,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
    }

    public func externalInvokeDirectAsyncStackInput(
        _ closure: ExternalDirectAsyncStackInputClosure
    ) async -> Int {
        await closure(1, 2, 3, 4, 5, 6).first
    }
#endif
