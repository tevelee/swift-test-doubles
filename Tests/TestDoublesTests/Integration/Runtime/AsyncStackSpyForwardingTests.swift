import Testing
@testable import TestDoubles

struct AsyncForwardingWideValue: Sendable {
    let first: Int
    let second: Int
}

struct AsyncForwardingPaddedValue: Sendable {
    let word: UInt64
    let byte: UInt8
}

#if arch(x86_64)
    protocol FirstSpilledAsyncForwardingProbe: Sendable {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int
        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int
    }

    protocol ThrowingSpilledAsyncForwardingProbe: Sendable {
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async throws -> Int
    }

    struct RealFirstSpilledAsyncForwardingProbe:
        FirstSpilledAsyncForwardingProbe
    {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int { a6 }

        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int {
            await Task.yield()
            return a6
        }
    }

    struct RealThrowingSpilledAsyncForwardingProbe:
        ThrowingSpilledAsyncForwardingProbe
    {
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async throws -> Int {
            throw AsyncStackUntypedError.failed(a6)
        }
    }

    protocol SecondSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async -> Int
    }

    struct RealSecondSpilledAsyncForwardingProbe:
        SecondSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async -> Int { a7 }
    }

    protocol WideSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ value: AsyncForwardingWideValue
        ) async -> Int
    }

    struct RealWideSpilledAsyncForwardingProbe:
        WideSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ value: AsyncForwardingWideValue
        ) async -> Int { value.second }
    }

    protocol PaddedSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ value: AsyncForwardingPaddedValue
        ) async -> Int
    }

    struct RealPaddedSpilledAsyncForwardingProbe:
        PaddedSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ value: AsyncForwardingPaddedValue
        ) async -> Int { Int(value.byte) }
    }

    protocol TypedErrorSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int,
            _ a3: Int, _ a4: Int, _ a5: Int
        ) async throws(AsyncStackLargeError) -> Int
    }

    struct RealTypedErrorSpilledAsyncForwardingProbe:
        TypedErrorSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int,
            _ a3: Int, _ a4: Int, _ a5: Int
        ) async throws(AsyncStackLargeError) -> Int { a5 }
    }

    protocol AccessorSpilledAsyncForwardingProbe: Sendable {
        subscript(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) -> Int { get async }
    }

    struct RealAccessorSpilledAsyncForwardingProbe:
        AccessorSpilledAsyncForwardingProbe
    {
        subscript(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) -> Int {
            get async { a6 }
        }
    }

    private func forwardedImmediate(
        _ probe: any FirstSpilledAsyncForwardingProbe
    ) async -> Int {
        await probe.immediate(1, 2, 3, 4, 5, 6, 0x7172_7374_7576_7778)
    }

    private func forwardedSuspending(
        _ probe: any FirstSpilledAsyncForwardingProbe
    ) async -> Int {
        await probe.suspending(1, 2, 3, 4, 5, 6, 0x6162_6364_6566_6768)
    }

#else
    protocol FirstSpilledAsyncForwardingProbe: Sendable {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int
        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int
    }

    protocol ThrowingSpilledAsyncForwardingProbe: Sendable {
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async throws -> Int
    }

    struct RealFirstSpilledAsyncForwardingProbe:
        FirstSpilledAsyncForwardingProbe
    {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int { a8 }

        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int {
            await Task.yield()
            return a8
        }
    }

    struct RealThrowingSpilledAsyncForwardingProbe:
        ThrowingSpilledAsyncForwardingProbe
    {
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async throws -> Int {
            throw AsyncStackUntypedError.failed(a8)
        }
    }

    protocol SecondSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
        ) async -> Int
    }

    struct RealSecondSpilledAsyncForwardingProbe:
        SecondSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
        ) async -> Int { a9 }
    }

    protocol WideSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int,
            _ value: AsyncForwardingWideValue
        ) async -> Int
    }

    struct RealWideSpilledAsyncForwardingProbe:
        WideSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int,
            _ value: AsyncForwardingWideValue
        ) async -> Int { value.second }
    }

    protocol PaddedSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int,
            _ value: AsyncForwardingPaddedValue
        ) async -> Int
    }

    struct RealPaddedSpilledAsyncForwardingProbe:
        PaddedSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int,
            _ value: AsyncForwardingPaddedValue
        ) async -> Int { Int(value.byte) }
    }

    protocol TypedErrorSpilledAsyncForwardingProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async throws(AsyncStackLargeError) -> Int
    }

    struct RealTypedErrorSpilledAsyncForwardingProbe:
        TypedErrorSpilledAsyncForwardingProbe
    {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async throws(AsyncStackLargeError) -> Int { a7 }
    }

    protocol AccessorSpilledAsyncForwardingProbe: Sendable {
        subscript(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) -> Int { get async }
    }

    struct RealAccessorSpilledAsyncForwardingProbe:
        AccessorSpilledAsyncForwardingProbe
    {
        subscript(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) -> Int {
            get async { a8 }
        }
    }

    private func forwardedImmediate(
        _ probe: any FirstSpilledAsyncForwardingProbe
    ) async -> Int {
        await probe.immediate(
            1, 2, 3, 4, 5, 6, 7, 8, 0x7172_7374_7576_7778
        )
    }

    private func forwardedSuspending(
        _ probe: any FirstSpilledAsyncForwardingProbe
    ) async -> Int {
        await probe.suspending(
            1, 2, 3, 4, 5, 6, 7, 8, 0x6162_6364_6566_6768
        )
    }

#endif

struct AsyncStackSpyForwardingTests {
    @Test func immediateTargetReceivesCopiedVisibleSpill() async throws {
        let target: any FirstSpilledAsyncForwardingProbe =
            RealFirstSpilledAsyncForwardingProbe()
        let spy = try Spy<any FirstSpilledAsyncForwardingProbe>(
            forwardingTo: target
        )

        #expect(
            await forwardedImmediate(spy()) == 0x7172_7374_7576_7778
        )
    }

    @Test func suspendedTargetRestoresTheCallerStackOnce() async throws {
        let target: any FirstSpilledAsyncForwardingProbe =
            RealFirstSpilledAsyncForwardingProbe()
        let spy = try Spy<any FirstSpilledAsyncForwardingProbe>(
            forwardingTo: target
        )

        #expect(
            await forwardedSuspending(spy()) == 0x6162_6364_6566_6768
        )
    }

    @Test func throwingVisibleSpillRemainsFailClosed() {
        let target: any ThrowingSpilledAsyncForwardingProbe =
            RealThrowingSpilledAsyncForwardingProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any ThrowingSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
        }
    }

    @Test func secondVisibleSpillRemainsFailClosed() {
        let target: any SecondSpilledAsyncForwardingProbe =
            RealSecondSpilledAsyncForwardingProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any SecondSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
        }
    }

    @Test func splitWideSpillRemainsFailClosed() {
        let target: any WideSpilledAsyncForwardingProbe =
            RealWideSpilledAsyncForwardingProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any WideSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
        }
    }

    @Test func paddedSpillRemainsFailClosed() {
        let target: any PaddedSpilledAsyncForwardingProbe =
            RealPaddedSpilledAsyncForwardingProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any PaddedSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
        }
    }

    @Test func typedErrorDestinationSpillRemainsFailClosed() {
        let target: any TypedErrorSpilledAsyncForwardingProbe =
            RealTypedErrorSpilledAsyncForwardingProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any TypedErrorSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
        }
    }

    @Test func asyncAccessorSpillRemainsFailClosed() {
        let target: any AccessorSpilledAsyncForwardingProbe =
            RealAccessorSpilledAsyncForwardingProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any AccessorSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
        }
    }
}
