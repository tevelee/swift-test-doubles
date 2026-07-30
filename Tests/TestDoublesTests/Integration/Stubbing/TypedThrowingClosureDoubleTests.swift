import TestDoubles
import Testing

private enum TypedClosureFailure: Error, Equatable {
    case rejected(Int)
}

@Suite struct TypedThrowingClosureDoubleTests {
    @Test func synchronousDoubleExposesAPreciseErrorChannel() throws {
        let double =
            TypedThrowingClosureDouble<
                Int,
                String,
                TypedClosureFailure
            >()
        double.when(equal: -1).thenThrow(
            TypedClosureFailure.rejected(-1)
        )
        double.whenAny().then { value in "value-\(value)" }

        let function: (Int) throws(TypedClosureFailure) -> String =
            double.function

        #expect(try function(1) == "value-1")
        #expect(throws: TypedClosureFailure.rejected(-1)) {
            try function(-1)
        }
        #expect(double.invocations == [1, -1])
    }

    @Test func asynchronousDoublePreservesTypedComputedFailures() async throws {
        let double =
            AsyncTypedThrowingClosureDouble<
                Int,
                String,
                TypedClosureFailure
            >()
        double.whenAny().then { value async throws in
            await Task.yield()
            guard value >= 0 else {
                throw TypedClosureFailure.rejected(value)
            }
            return "value-\(value)"
        }

        let function: @Sendable (Int) async throws(TypedClosureFailure) -> String =
            double.sendableFunction

        #expect(try await function(2) == "value-2")
        await #expect(throws: TypedClosureFailure.rejected(-2)) {
            try await function(-2)
        }
    }

    @Test func typedThrowsAdaptersExpandMultipleArguments() async throws {
        let synchronous =
            TypedThrowingClosureDouble<
                (Int, String),
                String,
                TypedClosureFailure
            >()
        synchronous.whenArguments { (value: Int, _: String) in
            value >= 0
        }.thenArguments { value, label in
            "\(label)-\(value)"
        }
        let syncFunction: (Int, String) throws(TypedClosureFailure) -> String =
            synchronous.expandedFunction()
        #expect(try syncFunction(1, "item") == "item-1")

        let asynchronous =
            AsyncTypedThrowingClosureDouble<
                (Int, Int, Int),
                Int,
                TypedClosureFailure
            >()
        asynchronous.whenAny().thenArguments { a, b, c in
            a + b + c
        }
        let asyncFunction: (Int, Int, Int) async throws(TypedClosureFailure) -> Int =
            asynchronous.expandedFunction()
        #expect(try await asyncFunction(1, 2, 3) == 6)
    }

    @Test func typedThrowsSpyForwardsUnmatchedCalls() throws {
        let spy =
            TypedThrowingClosureSpy<
                Int,
                String,
                TypedClosureFailure
            >(
                forwardingTo: { value throws(TypedClosureFailure) in
                    guard value >= 0 else {
                        throw .rejected(value)
                    }
                    return "live-\(value)"
                }
            )
        let calls = spy.whenAny()
        spy.when(equal: 1).thenReturn("override")

        #expect(try spy(1) == "override")
        #expect(try spy(2) == "live-2")
        #expect(calls.interactions.stubbed.arguments() == [1])
        #expect(calls.interactions.forwarded.arguments() == [2])
    }
}
