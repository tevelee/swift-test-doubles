import Testing
@testable import TestDoubles

private protocol HandlerArityProbe: Sendable {
    func zero() -> Int
    func one(_ a: Int) -> Int
    func two(_ a: Int, _ b: Int) -> Int
    func three(_ a: Int, _ b: Int, _ c: Int) -> Int
    func four(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Int
    func five(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) -> Int
    func six(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int) -> Int
    func seven(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int) -> Int
    func throwing(_ value: Int) throws -> Int
    func asynchronous(_ value: Int) async -> Int
    func asyncThrowing(_ value: Int) async throws -> Int
}

private protocol DoNothingProbe: Sendable {
    func synchronous(_ value: Int)
    func throwing(_ value: Int) throws
    func asynchronous(_ value: Int) async
    func asyncThrowing(_ value: Int) async throws
}

private struct HandlerError: Error, Equatable {
    let value: Int
}

private enum FixedBehaviorOutcome: Equatable, Sendable {
    case value(Int)
    case failure(HandlerError)
    case unexpectedError(String)
}

@Suite struct CallPatternTests {
    @Test func typedOutcomesExposeReturnsErrorsAndEntryOrder() throws {
        let stub = try makeHandlerArityStub()
        let pattern = stub.when { try $0.throwing(Match.any()) }
        pattern.then { (value: Int) throws in
            guard value >= 0 else { throw HandlerError(value: value) }
            return value * 2
        }

        let probe: any HandlerArityProbe = stub()
        #expect(try probe.throwing(2) == 4)
        #expect(throws: HandlerError(value: -1)) {
            try probe.throwing(-1)
        }

        #expect(pattern.results() == [4])
        #expect(pattern.errors(ofType: HandlerError.self) == [HandlerError(value: -1)])
        let outcomes = pattern.outcomes()
        #expect(outcomes.count == 2)
        guard case .returned(4) = outcomes[0] else {
            Issue.record("Expected the first call to return 4")
            return
        }
        guard case .threw(let error as HandlerError) = pattern.lastOutcome else {
            Issue.record("Expected the last call to throw HandlerError")
            return
        }
        #expect(error == HandlerError(value: -1))
    }

    @Test func terminalInteractionsInferTypedResultsFromContext() throws {
        let stub = try makeHandlerArityStub()
        let calls = stub.when { $0.one(Match.any()) }.thenReturn(42)
        let probe: any HandlerArityProbe = stub()

        #expect(probe.one(0) == 42)
        let results: [Int] = calls.results()
        #expect(results == [42])
        guard case .returned(42) = calls.lastOutcome(as: Int.self) else {
            Issue.record("Expected the terminal interaction to return 42")
            return
        }
    }

    @Test func invocationTimingRecordsEntryCompletionAndDuration() throws {
        let stub = try makeHandlerArityStub()
        let pattern = stub.when { $0.one(Match.any()) }
        pattern.thenReturn(42)
        let probe: any HandlerArityProbe = stub()

        #expect(probe.one(0) == 42)

        let timings = pattern.timings()
        #expect(timings.count == 1)
        let timing = try #require(timings.first)
        let completedAt = try #require(timing.completedAt)
        #expect(timing.startedAt <= completedAt)
        #expect(try #require(timing.duration) >= .zero)

        let events = stub.history.timeline.events
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.startedAt == timing.startedAt)
        #expect(event.completedAt == timing.completedAt)
        #expect(event.duration == timing.duration)
    }

    @Test func completionWaiterResumesAfterAsyncHandlerReturns() async throws {
        let stub = try makeHandlerArityStub()
        let pattern = await stub.when {
            await $0.asynchronous(Match.any())
        }
        pattern.then { (value: Int) async -> Int in
            try? await ContinuousClock().sleep(for: .milliseconds(25))
            return value * 2
        }
        let probe: any HandlerArityProbe = stub()

        let task = Task { await probe.asynchronous(21) }
        await pattern.interactions.waitForCompletion(
            count: 1,
            within: .seconds(1)
        )

        #expect(pattern.results() == [42])
        #expect(await task.value == 42)
    }

    @Test func completionOrderIsIndependentFromInvocationEntryOrder() async throws {
        let stub = try makeHandlerArityStub()
        let slow = await stub.when {
            await $0.asynchronous(Match.equal(1))
        }
        slow.then { (_: Int) async -> Int in
            try? await ContinuousClock().sleep(for: .milliseconds(50))
            return 1
        }
        let fast = await stub.when {
            await $0.asynchronous(Match.equal(2))
        }
        fast.then { (_: Int) async -> Int in
            try? await ContinuousClock().sleep(for: .milliseconds(5))
            return 2
        }
        let probe: any HandlerArityProbe = stub()

        let slowTask = Task { await probe.asynchronous(1) }
        await slow.verify(1..., within: .seconds(1))
        let fastTask = Task { await probe.asynchronous(2) }
        #expect(await fastTask.value == 2)
        #expect(await slowTask.value == 1)

        InvocationOrder {
            slow
            fast
        }
        CompletionOrder {
            fast
            slow
        }

        let completionEvents = stub.history.completionTimeline.events
        #expect(completionEvents.map(\.arguments) == [["2"], ["1"]])
        #expect(
            completionEvents.compactMap(\.completionSequence)
                == completionEvents.compactMap(\.completionSequence).sorted()
        )
    }

    @Test func callStackCaptureIsOptInAndFrameLimited() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }.thenReturn(42)
        let probe: any HandlerArityProbe = stub()

        _ = probe.one(1)
        stub.captureCallStacks(maxFrames: 4)
        _ = probe.one(2)

        let events = stub.history.timeline.events
        #expect(events.count == 2)
        #expect(events[0].callStack == nil)
        let stack = try #require(events[1].callStack)
        #expect(stack.isEmpty == false)
        #expect(stack.count <= 4)
    }

    @Test func typedThenSupportsZeroThroughSevenArguments() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.zero() }.then { 0 }
        stub.when { $0.one(Match.any()) }.then { (a: Int) in a }
        stub.when { $0.two(Match.any(), Match.any()) }.then { (a: Int, b: Int) in a + b }
        stub.when { $0.three(Match.any(), Match.any(), Match.any()) }.then {
            (a: Int, b: Int, c: Int) in a + b + c
        }
        stub.when { $0.four(Match.any(), Match.any(), Match.any(), Match.any()) }.then {
            (a: Int, b: Int, c: Int, d: Int) in a + b + c + d
        }
        stub.when { $0.five(Match.any(), Match.any(), Match.any(), Match.any(), Match.any()) }.then {
            (a: Int, b: Int, c: Int, d: Int, e: Int) in a + b + c + d + e
        }
        stub.when { $0.six(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any()) }.then {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in
            a + b + c + d + e + f
        }
        stub.when { $0.seven(Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any(), Match.any()) }.then {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) in
            a + b + c + d + e + f + g
        }

        let probe: any HandlerArityProbe = stub()
        #expect(probe.zero() == 0)
        #expect(probe.one(1) == 1)
        #expect(probe.two(1, 2) == 3)
        #expect(probe.three(1, 2, 3) == 6)
        #expect(probe.four(1, 2, 3, 4) == 10)
        #expect(probe.five(1, 2, 3, 4, 5) == 15)
        #expect(probe.six(1, 2, 3, 4, 5, 6) == 21)
        #expect(probe.seven(1, 2, 3, 4, 5, 6, 7) == 28)
    }

    @Test func unifiedThenSupportsThrowingAsyncAndAsyncThrowingHandlers() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { try $0.throwing(Match.any()) }.then { (value: Int) throws in
            if value < 0 { throw HandlerError(value: value) }
            return value * 2
        }
        await stub.when { await $0.asynchronous(Match.any()) }.then {
            (value: Int) async throws -> Int in
            await Task.yield()
            return value + 1
        }
        await stub.when { try await $0.asyncThrowing(Match.any()) }.then {
            (value: Int) async throws -> Int in
            await Task.yield()
            if value < 0 { throw HandlerError(value: value) }
            return value + 2
        }

        let probe: any HandlerArityProbe = stub()
        #expect(try probe.throwing(21) == 42)
        #expect(throws: HandlerError.self) { try probe.throwing(-1) }
        #expect(await probe.asynchronous(41) == 42)
        #expect(try await probe.asyncThrowing(40) == 42)
        await #expect(throws: HandlerError.self) {
            try await probe.asyncThrowing(-2)
        }
    }

    @Test func terminalHandlerCanBeSavedAndObserved() throws {
        let stub = try makeHandlerArityStub()
        let calls = stub.when { $0.one(Match.any()) }.then { (value: Int) in
            value * 2
        }

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(10) == 20)
        #expect(probe.one(21) == 42)

        calls.verify(2 ... 2)
        let arguments: [Int] = calls.arguments()
        #expect(arguments == [10, 21])
    }

    @Test func thenReturnSequenceServesConsecutiveValuesAndRepeatsTheLast() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }.thenReturn(1, 2, 3)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 1)
        #expect(probe.one(0) == 2)
        #expect(probe.one(0) == 3)
        #expect(probe.one(0) == 3)
    }

    @Test func thenReturnSequenceServesAsyncRequirements() async throws {
        let stub = try makeHandlerArityStub()
        await stub.when { try await $0.asyncThrowing(Match.any()) }.thenReturn(1, 2)

        let probe: any HandlerArityProbe = stub()
        #expect(try await probe.asyncThrowing(0) == 1)
        #expect(try await probe.asyncThrowing(0) == 2)
        #expect(try await probe.asyncThrowing(0) == 2)
    }

    @Test func behaviorChainMixesReturnsAndErrorsThenRepeatsTheLast() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { try $0.throwing(Match.any()) }
            .thenReturn(1)
            .thenThrow(HandlerError(value: 2))
            .thenReturn(3, 4)
        await stub.when { try await $0.asyncThrowing(Match.any()) }
            .thenThrow(HandlerError(value: 5))
            .thenReturn(6)

        let probe: any HandlerArityProbe = stub()
        #expect(try probe.throwing(0) == 1)
        #expect(throws: HandlerError(value: 2)) { try probe.throwing(0) }
        #expect(try probe.throwing(0) == 3)
        #expect(try probe.throwing(0) == 4)
        #expect(try probe.throwing(0) == 4)

        await #expect(throws: HandlerError(value: 5)) {
            try await probe.asyncThrowing(0)
        }
        #expect(try await probe.asyncThrowing(0) == 6)
        #expect(try await probe.asyncThrowing(0) == 6)
    }

    @Test func concurrentCallsReserveEachMixedBehaviorOnce() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { try $0.throwing(Match.any()) }
            .thenReturn(1)
            .thenThrow(HandlerError(value: 2))
            .thenReturn(3)
        let probe: any HandlerArityProbe = stub()

        let outcomes = await withTaskGroup(
            of: FixedBehaviorOutcome.self,
            returning: [FixedBehaviorOutcome].self
        ) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    do {
                        return .value(try probe.throwing(0))
                    } catch let error as HandlerError {
                        return .failure(error)
                    } catch {
                        return .unexpectedError(String(reflecting: error))
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(outcomes.filter { $0 == .value(1) }.count == 1)
        #expect(outcomes.filter { $0 == .failure(HandlerError(value: 2)) }.count == 1)
        #expect(outcomes.filter { $0 == .value(3) }.count == 48)
        #expect(outcomes.contains { if case .unexpectedError = $0 { true } else { false } } == false)
    }

    @Test func thenReturnSequencesAdvanceIndependentlyPerRegistration() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.equal(9)) }.thenReturn(90, 91)
        stub.when { $0.one(Match.any()) }.thenReturn(1, 2)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 1)
        #expect(probe.one(9) == 90)
        #expect(probe.one(0) == 2)
        #expect(probe.one(9) == 91)
        #expect(probe.one(0) == 2)
        #expect(probe.one(9) == 91)
    }

    @Test func timesServesABoundedRunThenAdvances() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }
            .thenReturn(0, times: 3)
            .thenReturn(9)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 0)
        #expect(probe.one(0) == 0)
        #expect(probe.one(0) == 0)
        #expect(probe.one(0) == 9)
        #expect(probe.one(0) == 9)
    }

    @Test func timesBoundedReturnCanBeTerminal() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }.thenReturn(3, times: 2)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 3)
        #expect(probe.one(0) == 3)
    }

    // Chaining after an unbounded entry (`times: 1...`, plain `thenReturn`/
    // `thenThrow` with no `times:` left standalone, or the variadic
    // thenReturn(_:_:_:), whose last entry is always unbounded) is a compile
    // error in one fluent expression: every overload that produces an
    // unbounded entry returns `CallInteractions`, which deliberately has no
    // behavior methods. A captured `StubBehaviorChain` can still reach an
    // append across separate statements, though — see
    // UnstubbedBehaviorExitTests.appendingAfterUnbounded for the runtime
    // guard that traps that aliasing case instead of silently discarding it.

    @Test func bareStandaloneRepeatsForever() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }.thenReturn(7)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 7)
        #expect(probe.one(0) == 7)
        #expect(probe.one(0) == 7)
    }

    @Test func bareChainedDefaultsToBoundedOnce() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }
            .thenReturn(1)
            .thenReturn(2)
            .thenReturn(3)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 1)
        #expect(probe.one(0) == 2)
        #expect(probe.one(0) == 3)
        #expect(probe.one(0) == 3)
    }

    @Test func completedBareChainCanBeSavedAndObserved() throws {
        let stub = try makeHandlerArityStub()
        let calls = stub.when { $0.one(Match.any()) }
            .thenReturn(1)
            .thenReturn(2)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(10) == 1)
        #expect(probe.one(20) == 2)
        #expect(probe.one(30) == 2)

        calls.verify(3 ... 3)
        let arguments: [Int] = calls.arguments()
        #expect(arguments == [10, 20, 30])
    }

    @Test func explicitRetryAndFallbackChainCanBeSavedAndObserved() throws {
        let stub = try makeHandlerArityStub()
        let calls = stub.when { try $0.throwing(Match.any()) }
            .thenThrow(HandlerError(value: 7), times: 2)
            .thenReturn(42, times: 1...)

        let probe: any HandlerArityProbe = stub()
        #expect(throws: HandlerError(value: 7)) { try probe.throwing(1) }
        #expect(throws: HandlerError(value: 7)) { try probe.throwing(2) }
        #expect(try probe.throwing(3) == 42)
        #expect(try probe.throwing(4) == 42)

        calls.verify(4 ... 4)
        let arguments: [Int] = calls.arguments()
        #expect(arguments == [1, 2, 3, 4])
    }

    @Test func finiteTimesServesExactlyThatManyCalls() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }.thenReturn(5, times: 3)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 5)
        #expect(probe.one(0) == 5)
        #expect(probe.one(0) == 5)
    }

    @Test func timesIntShorthandAdvancesWhenChained() throws {
        let stub = try makeHandlerArityStub()
        stub.when { try $0.throwing(Match.any()) }
            .thenReturn(1, times: 2)
            .thenThrow(HandlerError(value: 9), times: 2)
            .thenReturn(3)

        let probe: any HandlerArityProbe = stub()
        #expect(try probe.throwing(0) == 1)
        #expect(try probe.throwing(0) == 1)
        #expect(throws: HandlerError(value: 9)) { try probe.throwing(0) }
        #expect(throws: HandlerError(value: 9)) { try probe.throwing(0) }
        #expect(try probe.throwing(0) == 3)
        #expect(try probe.throwing(0) == 3)
    }

    @Test func variadicThenReturnWorksWithExactlyTwoValues() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(Match.any()) }.thenReturn(10, 20)

        let probe: any HandlerArityProbe = stub()
        #expect(probe.one(0) == 10)
        #expect(probe.one(0) == 20)
        #expect(probe.one(0) == 20)
    }

    @Test func concurrentCallsReserveEachRunExactlyItsCount() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { try $0.throwing(Match.any()) }
            .thenReturn(1, times: 10)
            .thenThrow(HandlerError(value: 2), times: 10)
            .thenReturn(3, times: 1...)
        let probe: any HandlerArityProbe = stub()

        let outcomes = await withTaskGroup(
            of: FixedBehaviorOutcome.self,
            returning: [FixedBehaviorOutcome].self
        ) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    do {
                        return .value(try probe.throwing(0))
                    } catch let error as HandlerError {
                        return .failure(error)
                    } catch {
                        return .unexpectedError(String(reflecting: error))
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(outcomes.filter { $0 == .value(1) }.count == 10)
        #expect(outcomes.filter { $0 == .failure(HandlerError(value: 2)) }.count == 10)
        #expect(outcomes.filter { $0 == .value(3) }.count == 80)
        #expect(outcomes.contains { if case .unexpectedError = $0 { true } else { false } } == false)
    }

    @Test func thenReturnAndThenShareResolutionRules() async throws {
        let stub = try makeHandlerArityStub()
        await stub.when { try await $0.asyncThrowing(Match.equal(42)) }.then {
            (_: Int) async throws -> Int in 100
        }
        await stub.when {
            try await $0.asyncThrowing(
                Match.matching(description: "positive", where: { $0 > 0 })
            )
        }.thenReturn(10)
        await stub.when { try await $0.asyncThrowing(Match.any()) }.then {
            (value: Int) async throws -> Int in value
        }

        let probe: any HandlerArityProbe = stub()
        #expect(try await probe.asyncThrowing(-1) == -1)
        #expect(try await probe.asyncThrowing(1) == 10)
        #expect(try await probe.asyncThrowing(42) == 100)
    }

    @Test func thenDoNothingSupportsEveryEffectCombination() async throws {
        let stub = try Stub<any DoNothingProbe>(
            .method(Int.self, returning: Void.self),
            .method(Int.self, returning: Void.self, isThrowing: true),
            .method(Int.self, returning: Void.self, isAsync: true),
            .method(Int.self, returning: Void.self, isThrowing: true, isAsync: true)
        )
        stub.when { $0.synchronous(Match.any()) }.thenDoNothing()
        stub.when { try $0.throwing(Match.any()) }.thenDoNothing()
        await stub.when { await $0.asynchronous(Match.any()) }.thenDoNothing()
        await stub.when { try await $0.asyncThrowing(Match.any()) }.thenDoNothing()

        let probe: any DoNothingProbe = stub()
        probe.synchronous(1)
        try probe.throwing(2)
        await probe.asynchronous(3)
        try await probe.asyncThrowing(4)

        stub.verify { $0.synchronous(1) }
        stub.verify { try $0.throwing(2) }
        await stub.verify { await $0.asynchronous(3) }
        await stub.verify { try await $0.asyncThrowing(4) }
    }

    @Test func completedDoNothingChainCanBeSavedAndObserved() throws {
        let stub = try Stub<any DoNothingProbe>(
            .method(Int.self, returning: Void.self),
            .method(Int.self, returning: Void.self, isThrowing: true),
            .method(Int.self, returning: Void.self, isAsync: true),
            .method(Int.self, returning: Void.self, isThrowing: true, isAsync: true)
        )
        let calls = stub.when { $0.synchronous(Match.any()) }
            .thenDoNothing(times: 2)
            .thenDoNothing(times: 1...)

        let probe: any DoNothingProbe = stub()
        probe.synchronous(1)
        probe.synchronous(2)
        probe.synchronous(3)

        calls.verify(3 ... 3)
        let arguments: [Int] = calls.arguments()
        #expect(arguments == [1, 2, 3])
    }

    @Test func fatalErrorTerminalCanBeSavedForVerification() throws {
        let stub = try makeHandlerArityStub()
        let forbidden = stub.when { $0.one(Match.any()) }
            .thenFatalError("must not be called")

        forbidden.verify(0 ... 0)
        #expect(forbidden.wasCalled == false)
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct CallPatternExitTests {
        @Test func timesBoundedReturnCanBeOverrun() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try makeHandlerArityStub()
                stub.when { $0.one(Match.any()) }.thenReturn(3, times: 2)

                let probe: any HandlerArityProbe = stub()
                _ = probe.one(0)
                _ = probe.one(0)
                _ = probe.one(0)
            }

            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("Explicit stub failure"))
            #expect(diagnostic.contains("Bounded stub behavior exhausted"))
        }

        @Test func fatalErrorChainedAfterAGenuinelyBoundedRunWorks() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try makeHandlerArityStub()
                stub.when { $0.one(Match.any()) }
                    .thenReturn(1, times: 2)
                    .thenFatalError("no more than 2 calls expected")

                let probe: any HandlerArityProbe = stub()
                _ = probe.one(0)
                _ = probe.one(0)
                _ = probe.one(0)
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("no more than 2 calls expected"))
        }
    }
#endif

private func makeHandlerArityStub() throws -> Stub<any HandlerArityProbe> {
    try Stub<any HandlerArityProbe>(
        .method(returning: Int.self),
        .method(Int.self, returning: Int.self),
        .method(Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, returning: Int.self, isThrowing: true),
        .method(Int.self, returning: Int.self, isAsync: true),
        .method(Int.self, returning: Int.self, isThrowing: true, isAsync: true)
    )
}
