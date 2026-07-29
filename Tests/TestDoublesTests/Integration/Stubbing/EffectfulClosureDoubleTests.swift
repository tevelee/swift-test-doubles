import Testing
@testable import TestDoubles

private enum EffectfulClosureFailure: Error, Equatable {
    case transient
}

@Suite struct EffectfulClosureDoubleTests {
    @Test func throwingClosureComposesErrorsComputedResultsAndFallbacks() throws {
        let formatter = ThrowingClosureDouble<Int, String>()
        let calls = formatter.whenAny()
            .thenThrow(EffectfulClosureFailure.transient)
            .then { (input: Int) throws in "computed-\(input)" }
            .thenReturn("fallback")

        let function: (Int) throws -> String = formatter.function
        #expect(throws: EffectfulClosureFailure.transient) {
            try function(1)
        }
        #expect(try function(2) == "computed-2")
        #expect(try function(3) == "fallback")
        #expect(formatter.invocations == [1, 2, 3])
        calls.verify(3 ... 3)
        formatter.history.verify(3 ... 3)
    }

    @Test func asyncClosureComposesComputedResultsAndFallbacks() async {
        let formatter = AsyncClosureDouble<Int, String>()
        let pattern = formatter.whenAny()
        let calls =
            pattern
            .then { input async in
                await Task.yield()
                return "computed-\(input)"
            }
            .thenReturn("fallback")

        let function: (Int) async -> String = formatter.function
        #expect(await function(1) == "computed-1")
        #expect(await function(2) == "fallback")
        #expect(pattern.arguments() == [1, 2])
        calls.verify(2 ... 2)
    }

    @Test func asyncThrowingClosureComposesAllEffectKinds() async throws {
        let loader = AsyncThrowingClosureDouble<String, Int>()
        let calls = loader.whenAny()
            .thenThrow(EffectfulClosureFailure.transient)
            .then { (input: String) async throws in
                await Task.yield()
                return input.count
            }
            .thenReturn(99)

        let function: (String) async throws -> Int = loader.function
        await #expect(throws: EffectfulClosureFailure.transient) {
            try await function("first")
        }
        #expect(try await function("swift") == 5)
        #expect(try await function("fallback") == 99)
        calls.verify(3 ... 3)
    }

    @Test func asyncClosureSuspensionUsesTheSharedControlSurface() async {
        let loader = AsyncClosureDouble<Int, String>()
        let suspension = loader.whenAny().thenSuspend()
        let task = Task { await loader(42) }

        await suspension.waitForCall(within: .seconds(1))
        suspension.resume(returning: "ready")

        #expect(await task.value == "ready")
        suspension.interactions.verify()
    }

    @Test func trailingCountedAsyncHandlerRepeatsImplicitly() async {
        let formatter = AsyncClosureDouble<Int, String>()
        let calls = formatter.whenAny().thenForEachCall { count async in
            await Task.yield()
            return "\(count)"
        }

        #expect(await formatter(1) == "1")
        #expect(await formatter(2) == "2")
        calls.verify(2 ... 2)
    }

    @Test func effectfulPatternsParticipateInFluentOrderVerification() async throws {
        let synchronous = ThrowingClosureDouble<Int, String>()
        let asynchronous = AsyncClosureDouble<Int, String>()
        let first = synchronous.whenAny()
        first.thenReturn("sync")
        let second = asynchronous.whenAny()
        second.thenReturn("async")

        _ = try synchronous(1)
        _ = await asynchronous(2)

        InvocationOrder()
            .verify(first)
            .verify(second)
            .verifyNoMoreInteractions()
    }
}
