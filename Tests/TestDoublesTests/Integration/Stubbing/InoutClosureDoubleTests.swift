import TestDoubles
import Testing

@Suite struct InoutClosureDoubleTests {
    @Test func handlersMutateAndReturnWhileRecordingEntryValues() {
        let double = InoutClosureDouble<Int, String>()
        let matching = double.when { $0 >= 0 }
        matching.then { value in
            value += 1
            return "updated-\(value)"
        }

        var value = 4
        let result = double.function(&value)

        #expect(result == "updated-5")
        #expect(value == 5)
        #expect(double.invocations == [4])
        #expect(matching.arguments() == [4])
        #expect(matching.mutatedValues() == [5])
        #expect(matching.results() == ["updated-5"])
    }

    @Test func behaviorChainsCanApplyDifferentMutations() {
        let double = InoutClosureDouble<Int, Void>()
        double.whenAny()
            .then { $0 += 1 }
            .thenMutate(to: 20)

        var first = 1
        var second = 2
        double(&first)
        double(&second)

        #expect(first == 2)
        #expect(second == 20)
    }

    @Test func fixedMutationConvenienceWritesBackAResult() {
        let double = InoutClosureDouble<String, Int>()
        double.when(equal: "draft").thenMutate(
            to: "published",
            returning: 42
        )

        var state = "draft"
        #expect(double(&state) == 42)
        #expect(state == "published")
    }

    @Test func forwardingSpyPreservesLiveInoutSemantics() {
        let spy = InoutClosureSpy<Int, String>(
            forwardingTo: { value in
                value *= 2
                return "live-\(value)"
            }
        )
        spy.when(equal: 1).thenMutate(
            to: 10,
            returning: "stubbed"
        )

        var stubbed = 1
        var forwarded = 3
        #expect(spy(&stubbed) == "stubbed")
        #expect(spy(&forwarded) == "live-6")
        #expect(stubbed == 10)
        #expect(forwarded == 6)

        let interactions = spy.whenAny().interactions
        #expect(interactions.stubbed.arguments() == [1])
        #expect(interactions.forwarded.arguments() == [3])
    }
}
