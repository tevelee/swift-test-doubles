import Testing
@testable import TestDoubles

protocol EnhancementAsyncLoader {
    func load() async -> Int
}

struct RealEnhancementAsyncLoader: EnhancementAsyncLoader {
    func load() async -> Int { 0 }
}

protocol EnhancementForwarder {
    func value(for key: String) -> String
}

struct RealEnhancementForwarder: EnhancementForwarder {
    func value(for key: String) -> String { "live-\(key)" }
}

protocol EnhancementThrowingAsyncLoader {
    func load() async throws -> Int
}

private enum EnhancementFailure: Error, Equatable {
    case expected
}

struct RealEnhancementThrowingAsyncLoader: EnhancementThrowingAsyncLoader {
    func load() async throws -> Int { 0 }
}

protocol EnhancementAsyncForwarder {
    func value(for key: String) async -> String
}

struct RealEnhancementAsyncForwarder: EnhancementAsyncForwarder {
    func value(for key: String) async -> String { "live-\(key)" }
}

protocol EnhancementClockVerifier: Sendable {
    func notify(_ value: Int)
}

struct RealEnhancementClockVerifier: EnhancementClockVerifier {
    func notify(_: Int) {}
}

@inline(never)
private func useLinkedAsyncLoader(_ value: any EnhancementAsyncLoader) async -> Int {
    await value.load()
}

@inline(never)
private func useLinkedThrowingAsyncLoader(
    _ value: any EnhancementThrowingAsyncLoader
) async throws -> Int {
    try await value.load()
}

@inline(never)
private func useLinkedForwarder(_ value: any EnhancementForwarder) -> String {
    value.value(for: "linked")
}

@inline(never)
private func useLinkedAsyncForwarder(_ value: any EnhancementAsyncForwarder) async -> String {
    await value.value(for: "linked")
}

@inline(never)
private func useLinkedClockVerifier(_ value: any EnhancementClockVerifier) {
    value.notify(0)
}

@Suite struct UserFacingEnhancementsTests {
    @Test func closureDoubleRecordsAndInjectsAUnaryClosure() {
        let formatter = ClosureDouble<Int, String>()
        formatter.when { $0 == 2 }.thenReturn("two")
        formatter.whenAny().then { "other-\($0)" }

        let function: (Int) -> String = formatter.function
        #expect(function(2) == "two")
        #expect(function(9) == "other-9")
        #expect(formatter.invocations == [2, 9])
        formatter.verify(.exactly(1), matching: { $0 == 2 })
    }

    @Test func callbackCaptureControlsCompletionLifetimeAndDelivery() {
        let callbacks = CallbackCapture<String>()
        var received: [String] = []
        callbacks.capture { received.append($0) }

        callbacks.invokeNext(repeating: 2, "ready")

        #expect(received == ["ready", "ready"])
        #expect(callbacks.pendingCount == 0)
        callbacks.assertReleased()
    }

    @Test func callbackCaptureInvokesAllAndReleasesCallbacks() {
        let callbacks = CallbackCapture<Int>()
        var received: [String] = []
        callbacks.capture { received.append("first:\($0)") }
        callbacks.capture { received.append("second:\($0)") }

        #expect(callbacks.pendingCount == 2)
        callbacks.invokeAll(3)
        #expect(received == ["first:3", "second:3"])
        #expect(callbacks.pendingCount == 0)

        callbacks.capture { received.append("discarded:\($0)") }
        callbacks.releaseAll()
        callbacks.assertReleased()
        #expect(callbacks.pendingCount == 0)
    }

    @Test func closureDoublesSupportLifecycleAndNullaryInjection() {
        let formatter = ClosureDouble<Int, String>()
        formatter.when(equal: 1).thenReturn("one")
        formatter.whenAny().then { "value:\($0)" }

        let function = formatter.function
        #expect(function(1) == "one")
        #expect(formatter(2) == "value:2")
        #expect(formatter.callCount(matching: { $0 > 0 }) == 2)
        formatter.verify(1..., equal: 1)
        formatter.clearRecordedInvocations()
        #expect(formatter.invocations.isEmpty)
        formatter.reset()

        let nullary = VoidClosureDouble<String>()
        nullary.when().thenReturn("ready")
        #expect(nullary.function() == "ready")
        #expect(nullary() == "ready")
        #expect(nullary.callCount == 2)

        let untouched = VoidClosureDouble<Void>()
        untouched.verifyNoInteractions()
    }

    @Test func finiteBehaviorQueueReportsRemainingAnswers() throws {
        let loader = try Stub<any ForEachCallLoader>()
        let queue = loader.when { $0.value(for: any()) }.thenQueue(1, 2)
        let service: any ForEachCallLoader = loader()

        #expect(queue.remainingAnswerCount == 2)
        #expect(service.value(for: "first") == 1)
        #expect(queue.remainingAnswerCount == 1)
        #expect(service.value(for: "second") == 2)
        #expect(queue.isExhausted)
        queue.assertExhausted()
    }

    @Test func throwingBehaviorQueuesExposeTheirRemainingAnswers() async throws {
        #expect(try await useLinkedThrowingAsyncLoader(RealEnhancementThrowingAsyncLoader()) == 0)
        let loader = try Stub<any EnhancementThrowingAsyncLoader>()
        let queue = await loader.when { try await $0.load() }
            .thenThrowQueue(EnhancementFailure.expected, EnhancementFailure.expected)
        let service: any EnhancementThrowingAsyncLoader = loader()

        #expect(queue.remainingAnswerCount == 2)
        await #expect(throws: EnhancementFailure.expected) { try await service.load() }
        #expect(queue.remainingAnswerCount == 1)
        await #expect(throws: EnhancementFailure.expected) { try await service.load() }
        #expect(queue.isExhausted)
        queue.assertExhausted()
    }

    @Test func manualClockControlsDelayedAsyncBehavior() async throws {
        #expect(await useLinkedAsyncLoader(RealEnhancementAsyncLoader()) == 0)
        let loader = try Stub<any EnhancementAsyncLoader>()
        let clock = ManualStubClock()
        await loader.when { await $0.load() }
            .thenReturn(42, after: .seconds(1), using: clock)

        let task = Task { await loader().load() }
        for _ in 0 ..< 100 where clock.pendingSleepCount == 0 {
            await Task.yield()
        }
        #expect(clock.pendingSleepCount == 1)
        clock.advance(by: .seconds(1))
        #expect(await task.value == 42)
    }

    @Test func manualClockDrivesDelayedFailuresAndSleepers() async throws {
        #expect(try await useLinkedThrowingAsyncLoader(RealEnhancementThrowingAsyncLoader()) == 0)
        let loader = try Stub<any EnhancementThrowingAsyncLoader>()
        let clock = ManualStubClock()
        await loader.when { try await $0.load() }
            .thenThrow(EnhancementFailure.expected, after: .seconds(1), using: clock)
        let service: any EnhancementThrowingAsyncLoader = loader()

        let invocation = Task { try await service.load() }
        for _ in 0 ..< 100 where clock.pendingSleepCount == 0 {
            await Task.yield()
        }
        #expect(clock.pendingSleepCount == 1)
        clock.advance(by: .seconds(1))
        await #expect(throws: EnhancementFailure.expected) { try await invocation.value }

        let sleeper = Task { () throws -> String in
            try await clock.sleep(for: .seconds(10))
            return "released"
        }
        for _ in 0 ..< 100 where clock.pendingSleepCount == 0 {
            await Task.yield()
        }
        clock.advanceToEnd()
        #expect(try await sleeper.value == "released")
        try await StubClocks.immediate.sleep(for: .zero)
    }

    @Test func timelinesIncludeTheMatchedRegistration() throws {
        let loader = try Stub<any ForEachCallLoader>()
        loader.when { $0.value(for: equal("timeline")) }.thenReturn(3)

        #expect(loader().value(for: "timeline") == 3)

        let timeline = loader.interactionTimeline()
        #expect(timeline.events.count == 1)
        #expect(timeline.events[0].dispatch == .stubbed)
        #expect(timeline.events[0].registration?.contains("value") == true)
        #expect(timeline.description.contains("stubbed"))

        let empty = try Stub<any ForEachCallLoader>()
        #expect(empty.interactionTimeline().description.contains("No interaction"))
    }

    @Test func spyCanAssertExactlyWhichCallsForwarded() throws {
        #expect(useLinkedForwarder(RealEnhancementForwarder()) == "live-linked")
        let spy: Spy<any EnhancementForwarder> = .make(forwardingTo: RealEnhancementForwarder())
        spy.when { $0.value(for: equal("override")) }.thenReturn("fixture")
        let service: any EnhancementForwarder = spy()

        #expect(service.value(for: "override") == "fixture")
        #expect(service.value(for: "live") == "live-live")

        spy.verifyOnlyForwarded {
            _ = $0.value(for: equal("live"))
        }
    }

    @Test func spyCanAssertThatNoCallsWereForwarded() throws {
        #expect(useLinkedForwarder(RealEnhancementForwarder()) == "live-linked")
        let spy: Spy<any EnhancementForwarder> = .make(forwardingTo: RealEnhancementForwarder())
        spy.when { $0.value(for: any()) }.thenReturn("fixture")

        #expect(spy().value(for: "overridden") == "fixture")
        spy.verifyNoForwardedInteractions()
    }

    @Test func asyncSpyVerifiesItsForwardingBoundary() async throws {
        #expect(await useLinkedAsyncForwarder(RealEnhancementAsyncForwarder()) == "live-linked")
        let spy: Spy<any EnhancementAsyncForwarder> = .make(
            forwardingTo: RealEnhancementAsyncForwarder()
        )
        let service: any EnhancementAsyncForwarder = spy()

        #expect(await service.value(for: "network") == "live-network")
        await spy.verifyOnlyForwarded {
            _ = await $0.value(for: equal("network"))
        }
    }

    @Test func parameterizedScenarioAppliesItsInput() throws {
        let scenario: ParameterizedStubScenario<any ForEachCallLoader, Int> = .init(named: "page") {
            stub,
            value in
            stub.when { $0.value(for: any()) }.thenReturn(value)
        }
        let loader = try Stub<any ForEachCallLoader>()

        scenario.apply(7, to: loader)

        #expect(loader().value(for: "input") == 7)
    }

    @Test func parameterizedScenariosCanBeBoundAndNamed() throws {
        let scenario: ParameterizedStubScenario<any ForEachCallLoader, Int> = .init(named: "page") {
            stub,
            value in
            stub.when { $0.value(for: any()) }.thenReturn(value)
        }
        let bound = scenario.scenario(for: 11)
        let loader = try Stub<any ForEachCallLoader>()

        #expect(scenario.name == "page")
        #expect(bound.name == "page")
        bound.apply(to: loader)
        #expect(loader().value(for: "input") == 11)
    }

    @Test func asyncParameterizedScenariosCanBeBoundAndNamed() async throws {
        #expect(await useLinkedAsyncLoader(RealEnhancementAsyncLoader()) == 0)
        let scenario: AsyncParameterizedStubScenario<any EnhancementAsyncLoader, Int> = .init(
            named: "async page"
        ) { stub, value in
            await stub.when { await $0.load() }.thenReturn(value)
        }
        let bound = scenario.scenario(for: 8)
        let loader = try Stub<any EnhancementAsyncLoader>()

        #expect(scenario.name == "async page")
        #expect(bound.name == "async page")
        await bound.apply(to: loader)
        #expect(await loader().load() == 8)
    }

    @Test func clockDrivenVerificationFinishesWhenTheCallArrives() async throws {
        useLinkedClockVerifier(RealEnhancementClockVerifier())
        let stub = try Stub<any EnhancementClockVerifier>()
        stub.when { $0.notify(any()) }.thenDoNothing()
        let service: any EnhancementClockVerifier = stub()
        let clock = ManualStubClock()

        let verification = Task {
            await stub.verify(within: .seconds(1), using: clock) {
                $0.notify(equal(7))
            }
        }
        for _ in 0 ..< 100 where clock.pendingSleepCount == 0 {
            await Task.yield()
        }
        #expect(clock.pendingSleepCount == 1)
        service.notify(7)
        await verification.value
        #expect(clock.pendingSleepCount == 0)
    }
}
