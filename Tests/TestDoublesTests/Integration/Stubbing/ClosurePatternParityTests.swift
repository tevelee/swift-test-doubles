import TestDoubles
import Testing

private enum ParityFailure: Error, Equatable {
    case rejected(Int)
}

private enum OtherParityFailure: Error, Equatable {
    case unrelated
}

@Suite struct ClosurePatternParityTests {
    @Test func `closure patterns expose forwarded and stubbed views`() {
        let spy = ClosureSpy<Int, String>(forwardingTo: { "live-\($0)" })
        let calls = spy.whenAny()
        spy.when(equal: 1).thenReturn("override")

        #expect(spy(1) == "override")
        #expect(spy(2) == "live-2")

        calls.forwarded.verify()
        #expect(calls.forwarded.arguments() == [2])
        calls.stubbed.verify()
        #expect(calls.stubbed.arguments() == [1])
    }

    @Test func `throwing closure patterns filter errors by type`() {
        let double = ThrowingClosureDouble<Int, String>()
        let calls = double.whenAny()
        calls
            .thenThrow(ParityFailure.rejected(1))
            .thenThrow(OtherParityFailure.unrelated)
            .thenReturn("ok")

        let function = double.function
        #expect(throws: ParityFailure.rejected(1)) { try function(1) }
        #expect(throws: OtherParityFailure.unrelated) { try function(2) }
        #expect((try? function(3)) == "ok")

        #expect(calls.errors().count == 2)
        #expect(calls.errors(ofType: ParityFailure.self) == [.rejected(1)])
        #expect(calls.errors(ofType: OtherParityFailure.self) == [.unrelated])
    }

    @Test func `closure patterns wait for completion of calls made elsewhere`() async {
        let double = AsyncClosureDouble<Int, String>()
        let calls = double.whenAny()
        calls.thenReturn("done")

        let function = double.function
        Task.detached { _ = await function(1) }

        await calls.waitForCompletion(within: .seconds(5))
        calls.verify()
        #expect(calls.results() == ["done"])
    }

    @Test func `closure patterns enable call-stack capture`() {
        let double = ClosureDouble<Int, String>()
        let calls = double.whenAny().captureCallStacks(maxFrames: 8)
        calls.thenReturn("value")

        _ = double.function(1)

        let frames = double.interactionTimeline().events.compactMap(\.callStack)
        #expect(frames.isEmpty == false)
    }

    @Test func `closure patterns drive an async stream controller`() async {
        let double = ClosureDouble<Int, AsyncStream<String>>()
        let calls = double.whenAny()
        let controller = calls.thenStream()

        var iterator = double.function(1).makeAsyncIterator()
        controller.yield("first")
        #expect(await iterator.next() == "first")
        controller.finish()
        #expect(await iterator.next() == nil)

        calls.verify()
    }

    @Test func `closure patterns drive a throwing stream controller`() async throws {
        let double = ThrowingClosureDouble<Int, AsyncThrowingStream<String, any Error>>()
        let calls = double.whenAny()
        let controller = calls.thenThrowingStream()

        var iterator = try double.function(1).makeAsyncIterator()
        controller.yield("first")
        #expect(try await iterator.next() == "first")
        controller.finish(throwing: ParityFailure.rejected(9))
        await #expect(throws: ParityFailure.rejected(9)) {
            try await iterator.next()
        }

        calls.verify()
    }
}
