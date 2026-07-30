import TestDoubles
import Testing

private enum ClosureSpyFailure: Error, Equatable {
    case rejected(Int)
}

@Suite struct ClosureSpyTests {
    @Test func synchronousSpyForwardsOverridesAndClassifiesCalls() {
        let spy = ClosureSpy<Int, String>(
            forwardingTo: { "live-\($0)" }
        )
        let calls = spy.whenAny()
        spy.when(equal: 1).thenReturn("override")

        #expect(spy(1) == "override")
        #expect(spy(2) == "live-2")
        #expect(calls.interactions.stubbed.arguments() == [1])
        #expect(calls.interactions.forwarded.arguments() == [2])
    }

    @Test func explicitForwardingPunchesThroughABroaderOverride() {
        let spy = ClosureSpy<Int, String>(
            forwardingTo: { "live-\($0)" }
        )
        spy.when(equal: 1).thenForward()
        spy.whenAny().thenReturn("override")

        #expect(spy(1) == "live-1")
        #expect(spy(2) == "override")
    }

    @Test func throwingSpyPreservesForwardedErrors() throws {
        let spy = ThrowingClosureSpy<Int, String>(
            forwardingTo: { value throws in
                guard value >= 0 else {
                    throw ClosureSpyFailure.rejected(value)
                }
                return "live-\(value)"
            }
        )
        spy.when(equal: 1).thenReturn("override")

        #expect(try spy(1) == "override")
        #expect(try spy(2) == "live-2")
        #expect(throws: ClosureSpyFailure.rejected(-1)) {
            try spy(-1)
        }
    }

    @Test func asynchronousSpiesForwardAndOverride() async throws {
        let asynchronous = AsyncClosureSpy<Int, String>(
            forwardingTo: { value in
                await Task.yield()
                return "live-\(value)"
            }
        )
        asynchronous.when(equal: 1).thenReturn("override")

        let throwing = AsyncThrowingClosureSpy<Int, String>(
            forwardingTo: { value throws in
                await Task.yield()
                guard value >= 0 else {
                    throw ClosureSpyFailure.rejected(value)
                }
                return "live-\(value)"
            }
        )
        throwing.when(equal: 1).thenReturn("override")

        #expect(await asynchronous(1) == "override")
        #expect(await asynchronous(2) == "live-2")
        #expect(try await throwing(1) == "override")
        #expect(try await throwing(2) == "live-2")
        await #expect(throws: ClosureSpyFailure.rejected(-1)) {
            try await throwing(-1)
        }
    }
}
