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

    private func configureImmediate(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async {
        await stub.when {
            await $0.immediate(any(), any(), any(), any(), any(), any(), equal(7))
        }.thenReturn(28)
    }

    private func callImmediate(_ probe: any FirstSpilledAsyncStubProbe) async -> Int {
        await probe.immediate(1, 2, 3, 4, 5, 6, 7)
    }

    private func suspendingBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            await $0.suspending(any(), any(), any(), any(), any(), any(), any())
        }.thenSuspend()
    }

    private func callSuspending(_ probe: any FirstSpilledAsyncStubProbe) async -> Int {
        await probe.suspending(1, 2, 3, 4, 5, 6, 7)
    }

    private func throwingBehavior(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async -> StubSuspension<Int> {
        await stub.when {
            try await $0.throwing(any(), any(), any(), any(), any(), any(), any())
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
            await $0.indirect(any(), any(), any(), any(), any(), any())
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
            try await $0.typed(any(), any(), any(), any(), any(), any())
        }.thenSuspend()
    }

    private func callTyped(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async throws(AsyncStackLargeError) -> Int {
        try await probe.typed(1, 2, 3, 4, 5, 6)
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

    private func configureImmediate(
        _ stub: Stub<any FirstSpilledAsyncStubProbe>
    ) async {
        await stub.when {
            await $0.immediate(
                any(), any(), any(), any(), any(), any(), any(), any(), equal(9)
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
                any(), any(), any(), any(), any(), any(), any(), any(), any()
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
                any(), any(), any(), any(), any(), any(), any(), any(), any()
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
            await $0.indirect(any(), any(), any(), any(), any(), any(), any(), any())
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
            try await $0.typed(any(), any(), any(), any(), any(), any(), any(), any())
        }.thenSuspend()
    }

    private func callTyped(
        _ probe: any FirstSpilledAsyncStubProbe
    ) async throws(AsyncStackLargeError) -> Int {
        try await probe.typed(1, 2, 3, 4, 5, 6, 7, 8)
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

    @Test func secondSpilledWordStillFailsClosed() {
        _ = RealSecondSpilledAsyncStubProbe()
        #expect(throws: StubError.self) {
            _ = try Stub<any SecondSpilledAsyncStubProbe>()
        }
    }

    @Test func forwardingWithTypedErrorStackIngressStillFailsClosed() {
        let target: any FirstSpilledAsyncStubProbe =
            RealFirstSpilledAsyncStubProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any FirstSpilledAsyncStubProbe>(forwardingTo: target)
        }
    }
}
