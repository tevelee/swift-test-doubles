import Testing
@testable import TestDoubles

private protocol EnhancementAsyncLoader {
    func load() async -> Int
}

private struct RealEnhancementAsyncLoader: EnhancementAsyncLoader {
    func load() async -> Int { 0 }
}

private protocol EnhancementForwarder {
    func value(for key: String) -> String
}

private struct RealEnhancementForwarder: EnhancementForwarder {
    func value(for key: String) -> String { "live-\(key)" }
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

    @Test func manualClockControlsDelayedAsyncBehavior() async throws {
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

    @Test func timelinesIncludeTheMatchedRegistration() throws {
        let loader = try Stub<any ForEachCallLoader>()
        loader.when { $0.value(for: equal("timeline")) }.thenReturn(3)

        #expect(loader().value(for: "timeline") == 3)

        let timeline = loader.interactionTimeline()
        #expect(timeline.events.count == 1)
        #expect(timeline.events[0].dispatch == .stubbed)
        #expect(timeline.events[0].registration?.contains("value") == true)
    }

    @Test func spyCanAssertExactlyWhichCallsForwarded() throws {
        let spy: Spy<any EnhancementForwarder> = .make(forwardingTo: RealEnhancementForwarder())
        spy.when { $0.value(for: equal("override")) }.thenReturn("fixture")
        let service: any EnhancementForwarder = spy()

        #expect(service.value(for: "override") == "fixture")
        #expect(service.value(for: "live") == "live-live")

        spy.verifyOnlyForwarded {
            _ = $0.value(for: equal("live"))
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
}
