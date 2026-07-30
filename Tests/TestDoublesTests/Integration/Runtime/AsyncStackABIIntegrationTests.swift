import TestDoublesRuntime
import TestDoublesRuntimeMetadata
import Testing
@testable import TestDoubles

struct AsyncStackLargeResult: Equatable, Sendable {
    let first: Int
    let second: Int
    let third: Int
    let fourth: Int
    let fifth: Int
}

struct AsyncStackLargeError: Error, Equatable, Sendable {
    let first: Int
    let second: Int
    let third: Int
    let fourth: Int
    let fifth: Int
}

enum AsyncStackUntypedError: Error, Equatable {
    case failed(Int)
}

struct AsyncStackSplitValue: Sendable {
    let first: Int
    let second: Int
}

#if arch(x86_64)
    protocol FirstSpilledAsyncStubProbe: Sendable {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int
        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async throws -> Int
        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int,
            _ a3: Int, _ a4: Int, _ a5: Int
        ) async -> AsyncStackLargeResult
        func typed(
            _ a0: Int, _ a1: Int, _ a2: Int,
            _ a3: Int, _ a4: Int, _ a5: Int
        ) async throws(AsyncStackLargeError) -> Int
    }

    struct RealFirstSpilledAsyncStubProbe: FirstSpilledAsyncStubProbe {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int { 0 }

        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int { 0 }

        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async throws -> Int { 0 }

        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int,
            _ a3: Int, _ a4: Int, _ a5: Int
        ) async -> AsyncStackLargeResult {
            AsyncStackLargeResult(first: 0, second: 0, third: 0, fourth: 0, fifth: 0)
        }

        func typed(
            _ a0: Int, _ a1: Int, _ a2: Int,
            _ a3: Int, _ a4: Int, _ a5: Int
        ) async throws(AsyncStackLargeError) -> Int { 0 }
    }

    protocol SecondSpilledAsyncStubProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async -> Int
    }

    struct RealSecondSpilledAsyncStubProbe: SecondSpilledAsyncStubProbe {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async -> Int { 0 }
    }

    protocol WiderSpilledAsyncStubProbe: Sendable {
        func three(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
        ) async throws -> Int
        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int
        ) async -> AsyncStackLargeResult
    }

    struct RealWiderSpilledAsyncStubProbe: WiderSpilledAsyncStubProbe {
        func three(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int { 0 }

        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
        ) async throws -> Int { 0 }

        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int
        ) async -> AsyncStackLargeResult {
            AsyncStackLargeResult(first: 0, second: 0, third: 0, fourth: 0, fifth: 0)
        }
    }

    protocol SplitSpilledAsyncStubProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ split: AsyncStackSplitValue
        ) async -> Int
    }

    struct RealSplitSpilledAsyncStubProbe: SplitSpilledAsyncStubProbe {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ split: AsyncStackSplitValue
        ) async -> Int { 0 }
    }

    private func configureImmediate(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async {
        await stub.when {
            await $0.immediate(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.equal(7))
        }.thenReturn(28)
    }

    private func callImmediate(_ probe: any FirstSpilledAsyncStubProbe) async -> Int {
        await probe.immediate(1, 2, 3, 4, 5, 6, 7)
    }

    private func suspendingBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            await $0.suspending(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any())
        }.thenSuspend()
    }

    private func callSuspending(_ probe: any FirstSpilledAsyncStubProbe) async -> Int {
        await probe.suspending(1, 2, 3, 4, 5, 6, 7)
    }

    private func throwingBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.throwing(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any())
        }.thenSuspend()
    }

    private func callThrowing(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async throws -> Int {
        try await probe.throwing(1, 2, 3, 4, 5, 6, 7)
    }

    private func indirectBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<AsyncStackLargeResult> {
        await stub.when {
            await $0.indirect(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any())
        }.thenSuspend()
    }

    private func callIndirect(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async -> AsyncStackLargeResult {
        await probe.indirect(1, 2, 3, 4, 5, 6)
    }

    private func typedBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.typed(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any())
        }.thenSuspend()
    }

    private func callTyped(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async throws(AsyncStackLargeError) -> Int {
        try await probe.typed(1, 2, 3, 4, 5, 6)
    }

    private func configureSecondSpill(
        _ stub: Stub<any SecondSpilledAsyncStubProbe>
    ) async {
        await stub.when {
            await $0.call(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.equal(7), Match.equal(8)
            )
        }.thenReturn(36)
    }

    private func callSecondSpill(
        _ probe: any SecondSpilledAsyncStubProbe
    ) async -> Int {
        await probe.call(1, 2, 3, 4, 5, 6, 7, 8)
    }

    private func threeSpillBehavior(
        _ stub: Stub<any WiderSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            await $0.three(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(7), Match.equal(8), Match.equal(9)
            )
        }.thenSuspend()
    }

    private func callThreeSpills(
        _ probe: any WiderSpilledAsyncStubProbe
    ) async -> Int {
        await probe.three(1, 2, 3, 4, 5, 6, 7, 8, 9)
    }

    private func severalSpillThrowingBehavior(
        _ stub: Stub<any WiderSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.throwing(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(7), Match.equal(8), Match.equal(9), Match.equal(10), Match.equal(11), Match.equal(12)
            )
        }.thenSuspend()
    }

    private func callSeveralSpillThrowing(
        _ probe: any WiderSpilledAsyncStubProbe
    ) async throws -> Int {
        try await probe.throwing(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
    }

    private func severalSpillIndirectBehavior(
        _ stub: Stub<any WiderSpilledAsyncStubProbe>
    ) async -> StubSuspension<AsyncStackLargeResult> {
        await stub.when {
            await $0.indirect(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(6), Match.equal(7), Match.equal(8), Match.equal(9), Match.equal(10), Match.equal(11)
            )
        }.thenSuspend()
    }

    private func callSeveralSpillIndirect(
        _ probe: any WiderSpilledAsyncStubProbe
    ) async -> AsyncStackLargeResult {
        await probe.indirect(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    }
#else
    protocol FirstSpilledAsyncStubProbe: Sendable {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int
        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async throws -> Int
        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async -> AsyncStackLargeResult
        func typed(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async throws(AsyncStackLargeError) -> Int
    }

    struct RealFirstSpilledAsyncStubProbe: FirstSpilledAsyncStubProbe {
        func immediate(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int { 0 }

        func suspending(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int { 0 }

        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async throws -> Int { 0 }

        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async -> AsyncStackLargeResult {
            AsyncStackLargeResult(first: 0, second: 0, third: 0, fourth: 0, fifth: 0)
        }

        func typed(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
        ) async throws(AsyncStackLargeError) -> Int { 0 }
    }

    protocol SecondSpilledAsyncStubProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
        ) async -> Int
    }

    struct RealSecondSpilledAsyncStubProbe: SecondSpilledAsyncStubProbe {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
        ) async -> Int { 0 }
    }

    protocol WiderSpilledAsyncStubProbe: Sendable {
        func three(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int
        ) async -> Int
        // swiftlint:disable:next function_parameter_count
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int,
            _ a12: Int, _ a13: Int
        ) async throws -> Int
        // swiftlint:disable:next function_parameter_count
        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int,
            _ a12: Int
        ) async -> AsyncStackLargeResult
    }

    struct RealWiderSpilledAsyncStubProbe: WiderSpilledAsyncStubProbe {
        func three(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int
        ) async -> Int { 0 }

        // swiftlint:disable:next function_parameter_count
        func throwing(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int,
            _ a12: Int, _ a13: Int
        ) async throws -> Int { 0 }

        // swiftlint:disable:next function_parameter_count
        func indirect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int,
            _ a12: Int
        ) async -> AsyncStackLargeResult {
            AsyncStackLargeResult(first: 0, second: 0, third: 0, fourth: 0, fifth: 0)
        }
    }

    protocol SplitSpilledAsyncStubProbe: Sendable {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int,
            _ split: AsyncStackSplitValue
        ) async -> Int
    }

    struct RealSplitSpilledAsyncStubProbe: SplitSpilledAsyncStubProbe {
        func call(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int,
            _ split: AsyncStackSplitValue
        ) async -> Int { 0 }
    }

    private func configureImmediate(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async {
        await stub.when {
            await $0.immediate(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.equal(9)
            )
        }.thenReturn(45)
    }

    private func callImmediate(_ probe: any FirstSpilledAsyncStubProbe) async -> Int {
        await probe.immediate(1, 2, 3, 4, 5, 6, 7, 8, 9)
    }

    private func suspendingBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            await $0.suspending(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any()
            )
        }.thenSuspend()
    }

    private func callSuspending(_ probe: any FirstSpilledAsyncStubProbe) async -> Int {
        await probe.suspending(1, 2, 3, 4, 5, 6, 7, 8, 9)
    }

    private func throwingBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.throwing(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any()
            )
        }.thenSuspend()
    }

    private func callThrowing(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async throws -> Int {
        try await probe.throwing(1, 2, 3, 4, 5, 6, 7, 8, 9)
    }

    private func indirectBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<AsyncStackLargeResult> {
        await stub.when {
            await $0.indirect(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any())
        }.thenSuspend()
    }

    private func callIndirect(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async -> AsyncStackLargeResult {
        await probe.indirect(1, 2, 3, 4, 5, 6, 7, 8)
    }

    private func typedBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.typed(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any())
        }.thenSuspend()
    }

    private func callTyped(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async throws(AsyncStackLargeError) -> Int {
        try await probe.typed(1, 2, 3, 4, 5, 6, 7, 8)
    }

    private func configureSecondSpill(
        _ stub: Stub<any SecondSpilledAsyncStubProbe>
    ) async {
        await stub.when {
            await $0.call(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(9), Match.equal(10)
            )
        }.thenReturn(55)
    }

    private func callSecondSpill(
        _ probe: any SecondSpilledAsyncStubProbe
    ) async -> Int {
        await probe.call(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    }

    private func threeSpillBehavior(
        _ stub: Stub<any WiderSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            await $0.three(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(9), Match.equal(10), Match.equal(11)
            )
        }.thenSuspend()
    }

    private func callThreeSpills(
        _ probe: any WiderSpilledAsyncStubProbe
    ) async -> Int {
        await probe.three(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    }

    private func severalSpillThrowingBehavior(
        _ stub: Stub<any WiderSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.throwing(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(9), Match.equal(10), Match.equal(11), Match.equal(12), Match.equal(13), Match.equal(14)
            )
        }.thenSuspend()
    }

    private func callSeveralSpillThrowing(
        _ probe: any WiderSpilledAsyncStubProbe
    ) async throws -> Int {
        try await probe.throwing(
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
        )
    }

    private func severalSpillIndirectBehavior(
        _ stub: Stub<any WiderSpilledAsyncStubProbe>
    ) async -> StubSuspension<AsyncStackLargeResult> {
        await stub.when {
            await $0.indirect(
                Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(),
                Match.equal(8), Match.equal(9), Match.equal(10), Match.equal(11), Match.equal(12), Match.equal(13)
            )
        }.thenSuspend()
    }

    private func callSeveralSpillIndirect(
        _ probe: any WiderSpilledAsyncStubProbe
    ) async -> AsyncStackLargeResult {
        await probe.indirect(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)
    }
#endif

struct AsyncStackABIIntegrationTests {
    @Test func firstSpilledArgumentDecodesOnTheImmediatePath() async throws {
        _ = RealFirstSpilledAsyncStubProbe()
        let stub = try Stub<any FirstSpilledAsyncStubProbe>()
        await configureImmediate(stub)

        #if arch(x86_64)
            #expect(await callImmediate(stub()) == 28)
        #else
            #expect(await callImmediate(stub()) == 45)
        #endif
    }

    @Test func firstSpilledArgumentSurvivesGenuineSuspension() async throws {
        _ = RealFirstSpilledAsyncStubProbe()
        let stub = try Stub<any FirstSpilledAsyncStubProbe>()
        let suspension = await suspendingBehavior(stub)
        let probe: any FirstSpilledAsyncStubProbe = stub()
        let task = Task { await callSuspending(probe) }

        await suspension.waitForCall()
        suspension.resume(returning: 91)
        #expect(await task.value == 91)
    }

    @Test func firstSpilledThrowingCallResumesWithAnError() async throws {
        _ = RealFirstSpilledAsyncStubProbe()
        let stub = try Stub<any FirstSpilledAsyncStubProbe>()
        let suspension = await throwingBehavior(stub)
        let probe: any FirstSpilledAsyncStubProbe = stub()
        let task = Task { try await callThrowing(probe) }

        await suspension.waitForCall()
        suspension.resume(throwing: AsyncStackUntypedError.failed(92))
        let error = await #expect(throws: AsyncStackUntypedError.self) {
            try await task.value
        }
        #expect(error == .failed(92))
    }

    @Test func firstSpilledCallPreservesAnIndirectResultDestination() async throws {
        _ = RealFirstSpilledAsyncStubProbe()
        let stub = try Stub<any FirstSpilledAsyncStubProbe>()
        let suspension = await indirectBehavior(stub)
        let probe: any FirstSpilledAsyncStubProbe = stub()
        let expected = AsyncStackLargeResult(
            first: 1,
            second: 2,
            third: 3,
            fourth: 4,
            fifth: 5
        )
        let task = Task { await callIndirect(probe) }

        await suspension.waitForCall()
        suspension.resume(returning: expected)
        #expect(await task.value == expected)
    }

    @Test func spilledTypedErrorDestinationSurvivesSuspension() async throws {
        _ = RealFirstSpilledAsyncStubProbe()
        let stub = try Stub<any FirstSpilledAsyncStubProbe>()
        let suspension = await typedBehavior(stub)
        let probe: any FirstSpilledAsyncStubProbe = stub()

        let success = Task { try await callTyped(probe) }
        await suspension.waitForCall()
        suspension.resume(returning: 93)
        #expect(try await success.value == 93)

        let expected = AsyncStackLargeError(
            first: 5,
            second: 4,
            third: 3,
            fourth: 2,
            fifth: 1
        )
        let failure = Task { try await callTyped(probe) }
        await suspension.waitForCall()
        suspension.resume(throwing: expected)
        let error = await #expect(throws: AsyncStackLargeError.self) {
            try await failure.value
        }
        #expect(error == expected)
    }

    @Test func twoCompleteSpilledWordsDecodeOnTheImmediatePath() async throws {
        _ = RealSecondSpilledAsyncStubProbe()
        let stub = try Stub<any SecondSpilledAsyncStubProbe>()
        await configureSecondSpill(stub)

        #if arch(x86_64)
            #expect(await callSecondSpill(stub()) == 36)
        #else
            #expect(await callSecondSpill(stub()) == 55)
        #endif
    }

    @Test func threeCompleteSpilledWordsSurviveGenuineSuspension() async throws {
        _ = RealWiderSpilledAsyncStubProbe()
        let stub = try Stub<any WiderSpilledAsyncStubProbe>()
        let suspension = await threeSpillBehavior(stub)
        let probe: any WiderSpilledAsyncStubProbe = stub()
        let task = Task { await callThreeSpills(probe) }

        await suspension.waitForCall()
        suspension.resume(returning: 94)
        #expect(await task.value == 94)
    }

    @Test func severalSpilledWordsPreserveUntypedThrowing() async throws {
        _ = RealWiderSpilledAsyncStubProbe()
        let stub = try Stub<any WiderSpilledAsyncStubProbe>()
        let suspension = await severalSpillThrowingBehavior(stub)
        let probe: any WiderSpilledAsyncStubProbe = stub()
        let task = Task { try await callSeveralSpillThrowing(probe) }

        await suspension.waitForCall()
        suspension.resume(throwing: AsyncStackUntypedError.failed(95))
        let error = await #expect(throws: AsyncStackUntypedError.self) {
            try await task.value
        }
        #expect(error == .failed(95))
    }

    @Test func severalSpilledWordsPreserveIndirectSuccessStorage() async throws {
        _ = RealWiderSpilledAsyncStubProbe()
        let stub = try Stub<any WiderSpilledAsyncStubProbe>()
        let suspension = await severalSpillIndirectBehavior(stub)
        let probe: any WiderSpilledAsyncStubProbe = stub()
        let expected = AsyncStackLargeResult(
            first: 9,
            second: 8,
            third: 7,
            fourth: 6,
            fifth: 5
        )
        let task = Task { await callSeveralSpillIndirect(probe) }

        await suspension.waitForCall()
        suspension.resume(returning: expected)
        #expect(await task.value == expected)
    }

    @Test func firstSplitWiderSpillFailsClosed() {
        _ = RealSplitSpilledAsyncStubProbe()
        #expect(throws: StubError.self) {
            _ = try Stub<any SplitSpilledAsyncStubProbe>()
        }
    }

    @Test func widerIngressPlanningSeparatesSupportedStackShapes() {
        func method(
            leadingIntegerCount: Int,
            trailingTypes: [Any.Type],
            conventions: [WitnessValueConvention]? = nil
        ) -> MethodDescriptor {
            let argumentTypes =
                Array(repeating: Int.self, count: leadingIntegerCount)
                + trailingTypes
            return MethodDescriptor(
                kind: .method,
                name: "call",
                index: 0,
                argumentTypes: argumentTypes,
                returnType: Int.self,
                argumentConventions: conventions,
                isAsync: true
            )
        }

        let splitX86 = method(
            leadingIntegerCount: 5,
            trailingTypes: [AsyncStackSplitValue.self]
        )
        let splitArm = method(
            leadingIntegerCount: 7,
            trailingTypes: [AsyncStackSplitValue.self]
        )
        let paddedX86 = method(
            leadingIntegerCount: 6,
            trailingTypes: [UInt32.self, UInt32.self]
        )
        let paddedArm = method(
            leadingIntegerCount: 8,
            trailingTypes: [UInt32.self, UInt32.self]
        )
        let vector = method(
            leadingIntegerCount: 0,
            trailingTypes: Array(repeating: SIMD4<Float>.self, count: 9)
        )
        let dependentConvention = WitnessValueConvention.associatedType(
            name: "Element"
        )
        let dependentX86 = method(
            leadingIntegerCount: 0,
            trailingTypes: Array(repeating: Int.self, count: 8),
            conventions: Array(repeating: dependentConvention, count: 8)
        )
        let dependentArm = method(
            leadingIntegerCount: 0,
            trailingTypes: Array(repeating: Int.self, count: 10),
            conventions: Array(repeating: dependentConvention, count: 10)
        )

        #expect(
            unsupportedRuntimeReason(for: splitX86, architecture: .x86_64)
                != nil
        )
        #expect(
            unsupportedRuntimeReason(for: splitArm, architecture: .arm64)
                != nil
        )
        #expect(
            unsupportedRuntimeReason(for: paddedX86, architecture: .x86_64)
                != nil
        )
        #expect(
            unsupportedRuntimeReason(for: paddedArm, architecture: .arm64)
                != nil
        )
        #expect(
            unsupportedRuntimeReason(for: vector, architecture: .x86_64)
                == nil
        )
        #expect(
            unsupportedRuntimeReason(for: vector, architecture: .arm64)
                == nil
        )
        #expect(
            unsupportedRuntimeReason(
                for: dependentX86,
                architecture: .x86_64
            ) != nil
        )
        #expect(
            unsupportedRuntimeReason(
                for: dependentArm,
                architecture: .arm64
            ) != nil
        )
    }

    @Test func forwardingWithTypedErrorStackIngressStillFailsClosed() {
        let target: any FirstSpilledAsyncStubProbe =
            RealFirstSpilledAsyncStubProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any FirstSpilledAsyncStubProbe>(forwardingTo: target)
        }
    }
}
