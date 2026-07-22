import Testing

@testable import TestDoubles

@Suite
struct RetainedRuntimeStateTests {
    @Test
    func retainedStateSurvivesUntilItIsConsumed() {
        final class State {}

        var state: State? = State()
        weak let weakState = state
        let pointer = RetainedRuntimeState.retain(state!)
        state = nil

        #expect(weakState != nil)
        #expect(
            RetainedRuntimeState.borrow(
                State.self,
                from: pointer,
                invalidTypeMessage: "unexpected state type"
            ) === weakState
        )

        var consumed: State? = RetainedRuntimeState.consume(
            State.self,
            from: pointer,
            invalidTypeMessage: "unexpected state type"
        )
        #expect(consumed === weakState)
        consumed = nil
        #expect(weakState == nil)
    }
}
