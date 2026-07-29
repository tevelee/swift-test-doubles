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

    @Test func throwingClosureForwardsEveryBehaviorShape() throws {
        let closure = ThrowingClosureDouble<Int, String>()

        closure.when(equal: 1)
            .thenReturn("once", times: 1)
            .thenReturn("fallback")
        closure.when(equal: 2).thenReturn("repeat", times: 1...)
        closure.when(equal: 3).thenReturn("first", "second", "last")
        let values = closure.when(equal: 4).thenQueue("queued-1", "queued-2")

        closure.when(equal: 5).then(times: 1) {
            (input: Int) throws -> String in "input-\(input)"
        }
        closure.when(equal: 6).then(times: 1...) {
            (input: Int) throws -> String in "repeating-\(input)"
        }
        closure.when(equal: 7).then(times: 1) {
            () throws -> String in "constant"
        }
        closure.when(equal: 8).then(times: 1...) {
            () throws -> String in "repeating-constant"
        }
        closure.when(equal: 9).thenForEachCall(times: 1) {
            (count: Int, input: Int) throws -> String in "\(count)-\(input)"
        }
        closure.when(equal: 10).thenForEachCall(times: 1...) {
            (count: Int, input: Int) throws -> String in "\(count)-\(input)"
        }
        closure.when(equal: 11).thenForEachCall(times: 1) {
            (count: Int) throws -> String in "count-\(count)"
        }
        closure.when(equal: 12).thenForEachCall(times: 1...) {
            (count: Int) throws -> String in "repeat-count-\(count)"
        }

        closure.when(equal: 13)
            .thenThrow(EffectfulClosureFailure.transient, times: 1)
            .thenReturn("recovered")
        closure.when(equal: 14)
            .thenThrow(EffectfulClosureFailure.transient, times: 1...)
        let errors = closure.when(equal: 15).thenThrowQueue(
            EffectfulClosureFailure.transient,
            EffectfulClosureFailure.transient
        )
        closure.when({ $0 < 0 }, describedBy: "negative")
            .thenFatalError("unreachable")

        #expect(try closure(1) == "once")
        #expect(try closure(1) == "fallback")
        #expect(try closure(2) == "repeat")
        #expect(try closure(2) == "repeat")
        #expect(try closure(3) == "first")
        #expect(try closure(3) == "second")
        #expect(try closure(3) == "last")
        #expect(try closure(3) == "last")
        #expect(try closure(4) == "queued-1")
        #expect(try closure(4) == "queued-2")
        #expect(values.isExhausted)
        #expect(try closure(5) == "input-5")
        #expect(try closure(6) == "repeating-6")
        #expect(try closure(7) == "constant")
        #expect(try closure(8) == "repeating-constant")
        #expect(try closure(9) == "1-9")
        #expect(try closure(10) == "1-10")
        #expect(try closure(11) == "count-1")
        #expect(try closure(12) == "repeat-count-1")
        #expect(throws: EffectfulClosureFailure.transient) { try closure(13) }
        #expect(try closure(13) == "recovered")
        #expect(throws: EffectfulClosureFailure.transient) { try closure(14) }
        #expect(throws: EffectfulClosureFailure.transient) { try closure(15) }
        #expect(throws: EffectfulClosureFailure.transient) { try closure(15) }
        #expect(errors.isExhausted)
    }

    @Test func asyncClosureForwardsEveryComputedBehaviorShape() async {
        let closure = AsyncClosureDouble<Int, String>()

        closure.when(equal: 1).then(times: 1) {
            (input: Int) -> String in "sync-\(input)"
        }
        closure.when(equal: 2).then(times: 1...) {
            (input: Int) -> String in "sync-repeat-\(input)"
        }
        closure.when(equal: 3).then(times: 1) {
            (input: Int) async -> String in
            await Task.yield()
            return "async-\(input)"
        }
        closure.when(equal: 4).then(times: 1...) {
            (input: Int) async -> String in
            await Task.yield()
            return "async-repeat-\(input)"
        }
        closure.when(equal: 5).then(times: 1) {
            () -> String in "sync-constant"
        }
        closure.when(equal: 6).then(times: 1...) {
            () -> String in "sync-repeating-constant"
        }
        closure.when(equal: 7).then(times: 1) {
            () async -> String in
            await Task.yield()
            return "async-constant"
        }
        closure.when(equal: 8).then(times: 1...) {
            () async -> String in
            await Task.yield()
            return "async-repeating-constant"
        }
        closure.when(equal: 9).thenForEachCall(times: 1) {
            (count: Int, input: Int) -> String in "\(count)-\(input)"
        }
        closure.when(equal: 10).thenForEachCall(times: 1...) {
            (count: Int, input: Int) -> String in "\(count)-\(input)"
        }
        closure.when(equal: 11).thenForEachCall(times: 1) {
            (count: Int) -> String in "count-\(count)"
        }
        closure.when(equal: 12).thenForEachCall(times: 1...) {
            (count: Int) -> String in "repeat-count-\(count)"
        }
        closure.when(equal: 13).thenForEachCall(times: 1) {
            (count: Int, input: Int) async -> String in
            await Task.yield()
            return "\(count)-async-\(input)"
        }
        closure.when(equal: 14).thenForEachCall(times: 1...) {
            (count: Int, input: Int) async -> String in
            await Task.yield()
            return "\(count)-async-repeat-\(input)"
        }
        closure.when(equal: 15).thenForEachCall(times: 1) {
            (count: Int) async -> String in
            await Task.yield()
            return "async-count-\(count)"
        }
        closure.when(equal: 16).thenForEachCall(times: 1...) {
            (count: Int) async -> String in
            await Task.yield()
            return "async-repeat-count-\(count)"
        }

        #expect(await closure(1) == "sync-1")
        #expect(await closure(2) == "sync-repeat-2")
        #expect(await closure(3) == "async-3")
        #expect(await closure(4) == "async-repeat-4")
        #expect(await closure(5) == "sync-constant")
        #expect(await closure(6) == "sync-repeating-constant")
        #expect(await closure(7) == "async-constant")
        #expect(await closure(8) == "async-repeating-constant")
        #expect(await closure(9) == "1-9")
        #expect(await closure(10) == "1-10")
        #expect(await closure(11) == "count-1")
        #expect(await closure(12) == "repeat-count-1")
        #expect(await closure(13) == "1-async-13")
        #expect(await closure(14) == "1-async-repeat-14")
        #expect(await closure(15) == "async-count-1")
        #expect(await closure(16) == "async-repeat-count-1")
    }

    @Test func asyncThrowingClosureForwardsEveryComputedBehaviorShape() async throws {
        let closure = AsyncThrowingClosureDouble<Int, String>()

        closure.when(equal: 1).then(times: 1) {
            (input: Int) throws -> String in "sync-\(input)"
        }
        closure.when(equal: 2).then(times: 1...) {
            (input: Int) throws -> String in "sync-repeat-\(input)"
        }
        closure.when(equal: 3).then(times: 1) {
            (input: Int) async throws -> String in
            await Task.yield()
            return "async-\(input)"
        }
        closure.when(equal: 4).then(times: 1...) {
            (input: Int) async throws -> String in
            await Task.yield()
            return "async-repeat-\(input)"
        }
        closure.when(equal: 5).then(times: 1) {
            () throws -> String in "sync-constant"
        }
        closure.when(equal: 6).then(times: 1...) {
            () throws -> String in "sync-repeating-constant"
        }
        closure.when(equal: 7).then(times: 1) {
            () async throws -> String in
            await Task.yield()
            return "async-constant"
        }
        closure.when(equal: 8).then(times: 1...) {
            () async throws -> String in
            await Task.yield()
            return "async-repeating-constant"
        }
        closure.when(equal: 9).thenForEachCall(times: 1) {
            (count: Int, input: Int) throws -> String in "\(count)-\(input)"
        }
        closure.when(equal: 10).thenForEachCall(times: 1...) {
            (count: Int, input: Int) throws -> String in "\(count)-\(input)"
        }
        closure.when(equal: 11).thenForEachCall(times: 1) {
            (count: Int) throws -> String in "count-\(count)"
        }
        closure.when(equal: 12).thenForEachCall(times: 1...) {
            (count: Int) throws -> String in "repeat-count-\(count)"
        }
        closure.when(equal: 13).thenForEachCall(times: 1) {
            (count: Int, input: Int) async throws -> String in
            await Task.yield()
            return "\(count)-async-\(input)"
        }
        closure.when(equal: 14).thenForEachCall(times: 1...) {
            (count: Int, input: Int) async throws -> String in
            await Task.yield()
            return "\(count)-async-repeat-\(input)"
        }
        closure.when(equal: 15).thenForEachCall(times: 1) {
            (count: Int) async throws -> String in
            await Task.yield()
            return "async-count-\(count)"
        }
        closure.when(equal: 16).thenForEachCall(times: 1...) {
            (count: Int) async throws -> String in
            await Task.yield()
            return "async-repeat-count-\(count)"
        }

        #expect(try await closure(1) == "sync-1")
        #expect(try await closure(2) == "sync-repeat-2")
        #expect(try await closure(3) == "async-3")
        #expect(try await closure(4) == "async-repeat-4")
        #expect(try await closure(5) == "sync-constant")
        #expect(try await closure(6) == "sync-repeating-constant")
        #expect(try await closure(7) == "async-constant")
        #expect(try await closure(8) == "async-repeating-constant")
        #expect(try await closure(9) == "1-9")
        #expect(try await closure(10) == "1-10")
        #expect(try await closure(11) == "count-1")
        #expect(try await closure(12) == "repeat-count-1")
        #expect(try await closure(13) == "1-async-13")
        #expect(try await closure(14) == "1-async-repeat-14")
        #expect(try await closure(15) == "async-count-1")
        #expect(try await closure(16) == "async-repeat-count-1")
    }

    @Test func effectfulFixedOutcomesAndControlBehaviorsForward() async throws {
        let asynchronous = AsyncClosureDouble<Int, String>()
        asynchronous.when(equal: 1)
            .thenReturn("once", after: nil, times: 1)
            .thenReturn("fallback")
        asynchronous.when(equal: 2)
            .thenReturn("repeat", after: nil, times: 1...)
        asynchronous.when(equal: 3).thenReturn("first", "last")
        asynchronous.when(equal: 4)
            .thenReturn("clocked", after: .zero, using: StubClocks.immediate)
        let asyncValues = asynchronous.when(equal: 5)
            .thenQueue("queued-1", "queued-2")
        asynchronous.when({ $0 == -1 }).thenFatalError()
        asynchronous.when({ $0 == -2 }).thenNeverReturn()
        _ = asynchronous.when({ $0 == -3 }).thenSuspend()
        asynchronous.when({ $0 == -4 })
            .thenAwaitCancellation(returning: "cancelled")

        #expect(await asynchronous(1) == "once")
        #expect(await asynchronous(1) == "fallback")
        #expect(await asynchronous(2) == "repeat")
        #expect(await asynchronous(3) == "first")
        #expect(await asynchronous(3) == "last")
        #expect(await asynchronous(3) == "last")
        #expect(await asynchronous(4) == "clocked")
        #expect(await asynchronous(5) == "queued-1")
        #expect(await asynchronous(5) == "queued-2")
        #expect(asyncValues.isExhausted)

        let throwing = AsyncThrowingClosureDouble<Int, String>()
        throwing.when(equal: 1)
            .thenReturn("once", after: nil, times: 1)
            .thenReturn("fallback")
        throwing.when(equal: 2)
            .thenReturn("repeat", after: nil, times: 1...)
        throwing.when(equal: 3).thenReturn("first", "last")
        throwing.when(equal: 4)
            .thenReturn("clocked", after: .zero, using: StubClocks.immediate)
        let throwingValues = throwing.when(equal: 5)
            .thenQueue("queued-1", "queued-2")
        throwing.when(equal: 6)
            .thenThrow(EffectfulClosureFailure.transient, times: 1)
            .thenReturn("recovered")
        throwing.when(equal: 7).thenThrow(
            EffectfulClosureFailure.transient,
            times: 1...
        )
        throwing.when(equal: 8).thenThrow(
            EffectfulClosureFailure.transient,
            after: .zero,
            using: StubClocks.immediate
        )
        let throwingErrors = throwing.when(equal: 9).thenThrowQueue(
            EffectfulClosureFailure.transient,
            EffectfulClosureFailure.transient
        )
        throwing.when({ $0 == -1 }).thenFatalError()
        throwing.when({ $0 == -2 }).thenNeverReturn()
        _ = throwing.when({ $0 == -3 }).thenSuspend()
        throwing.when({ $0 == -4 }).thenAwaitCancellation()
        throwing.when({ $0 == -5 })
            .thenAwaitCancellation(returning: "cancelled")
        throwing.when({ $0 == -6 })
            .thenAwaitCancellation(throwing: EffectfulClosureFailure.transient)

        #expect(try await throwing(1) == "once")
        #expect(try await throwing(1) == "fallback")
        #expect(try await throwing(2) == "repeat")
        #expect(try await throwing(3) == "first")
        #expect(try await throwing(3) == "last")
        #expect(try await throwing(3) == "last")
        #expect(try await throwing(4) == "clocked")
        #expect(try await throwing(5) == "queued-1")
        #expect(try await throwing(5) == "queued-2")
        #expect(throwingValues.isExhausted)
        await #expect(throws: EffectfulClosureFailure.transient) {
            try await throwing(6)
        }
        #expect(try await throwing(6) == "recovered")
        await #expect(throws: EffectfulClosureFailure.transient) {
            try await throwing(7)
        }
        await #expect(throws: EffectfulClosureFailure.transient) {
            try await throwing(8)
        }
        await #expect(throws: EffectfulClosureFailure.transient) {
            try await throwing(9)
        }
        await #expect(throws: EffectfulClosureFailure.transient) {
            try await throwing(9)
        }
        #expect(throwingErrors.isExhausted)
    }

    @Test func effectfulVoidBehaviorsForward() async throws {
        let synchronous = ThrowingClosureDouble<Int, Void>()
        synchronous.when(equal: 1)
            .thenDoNothing(times: 1)
            .thenDoNothing()
        synchronous.when(equal: 2).thenDoNothing(times: 1...)

        try synchronous(1)
        try synchronous(1)
        try synchronous(2)

        let asynchronous = AsyncClosureDouble<Int, Void>()
        asynchronous.when(equal: 1)
            .thenDoNothing(after: nil, times: 1)
            .thenDoNothing()
        asynchronous.when(equal: 2)
            .thenDoNothing(after: nil, times: 1...)
        asynchronous.when({ $0 < 0 }).thenAwaitCancellation()

        await asynchronous(1)
        await asynchronous(1)
        await asynchronous(2)

        let throwing = AsyncThrowingClosureDouble<Int, Void>()
        throwing.when(equal: 1)
            .thenDoNothing(after: nil, times: 1)
            .thenDoNothing()
        throwing.when(equal: 2)
            .thenDoNothing(after: nil, times: 1...)

        try await throwing(1)
        try await throwing(1)
        try await throwing(2)
    }

    @Test func effectfulObservationAndLifecycleSurfacesAreConsistent() async throws {
        let synchronous = ThrowingClosureDouble<Int, String>().named("sync")
        let syncPattern = synchronous.when(
            { $0.isMultiple(of: 2) },
            describedBy: "even"
        )
        syncPattern.thenReturn("even")
        #expect(try synchronous.function(2) == "even")
        #expect(syncPattern.wasCalled)
        #expect(syncPattern.callCount == 1)
        #expect(syncPattern.arguments() == [2])
        let _: InvocationStream<Int> = syncPattern.stream()
        syncPattern.verify()
        await syncPattern.verify(within: .seconds(1))
        await syncPattern.verify(
            within: .seconds(1),
            using: StubClocks.immediate
        )
        syncPattern.interactions.verify()
        synchronous.history.verify()
        synchronous.verifyNoUnusedStubs()
        synchronous.clearRecordedInvocations()
        #expect(synchronous.invocations.isEmpty)
        synchronous.clearConfiguredBehaviors()
        synchronous.reset()

        let asynchronous = AsyncClosureDouble<Int, String>().named("async")
        let asyncPattern = asynchronous.when(equal: 1)
        asyncPattern.thenReturn("one")
        #expect(await asynchronous.function(1) == "one")
        #expect(asyncPattern.wasCalled)
        #expect(asyncPattern.callCount == 1)
        #expect(asyncPattern.arguments() == [1])
        let _: InvocationStream<Int> = asyncPattern.stream()
        asyncPattern.verify()
        await asyncPattern.verify(within: .seconds(1))
        await asyncPattern.verify(
            within: .seconds(1),
            using: StubClocks.immediate
        )
        asyncPattern.interactions.verify()
        asynchronous.history.verify()
        asynchronous.verifyNoUnusedStubs()
        asynchronous.clearRecordedInvocations()
        #expect(asynchronous.invocations.isEmpty)
        asynchronous.clearConfiguredBehaviors()
        asynchronous.reset()

        let asyncThrowing =
            AsyncThrowingClosureDouble<Int, String>().named("async-throwing")
        let asyncThrowingPattern = asyncThrowing.when(equal: 1)
        asyncThrowingPattern.thenReturn("one")
        #expect(try await asyncThrowing.function(1) == "one")
        #expect(asyncThrowingPattern.wasCalled)
        #expect(asyncThrowingPattern.callCount == 1)
        #expect(asyncThrowingPattern.arguments() == [1])
        let _: InvocationStream<Int> = asyncThrowingPattern.stream()
        asyncThrowingPattern.verify()
        await asyncThrowingPattern.verify(within: .seconds(1))
        await asyncThrowingPattern.verify(
            within: .seconds(1),
            using: StubClocks.immediate
        )
        asyncThrowingPattern.interactions.verify()
        asyncThrowing.history.verify()
        asyncThrowing.verifyNoUnusedStubs()
        asyncThrowing.clearRecordedInvocations()
        #expect(asyncThrowing.invocations.isEmpty)
        asyncThrowing.clearConfiguredBehaviors()
        asyncThrowing.reset()
    }
}
