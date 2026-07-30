import TestDoubles
import Testing

private enum MainActorClosureFailure: Error, Equatable {
    case rejected
}

@Suite struct GlobalActorClosureDoubleTests {
    @MainActor
    @Test func synchronousViewHasMainActorIsolation() {
        let double =
            MainActorClosureDouble<Int, String>()
        double.whenAny().then { "value-\($0)" }

        let function: @MainActor @Sendable (Int) -> String =
            double.mainActorFunction

        #expect(function(3) == "value-3")
        #expect(double.invocations == [3])
    }

    @Test func mainActorViewCanBeCalledAcrossAnIsolationBoundary() async {
        let double =
            MainActorAsyncClosureDouble<Int, String>()
        double.whenAny().then { "value-\($0)" }
        let function: @MainActor @Sendable (Int) async -> String =
            double.mainActorFunction

        let value = await Task.detached {
            await function(4)
        }.value

        #expect(value == "value-4")
        #expect(double.invocations == [4])
    }

    @MainActor
    @Test func typedThrowsViewPreservesItsFailureType() {
        let double =
            MainActorTypedThrowingClosureDouble<
                Int,
                String,
                MainActorClosureFailure
            >()
        double.whenAny().thenThrow(
            MainActorClosureFailure.rejected
        )

        let function:
            @MainActor @Sendable (
                Int
            ) throws(MainActorClosureFailure) -> String =
                double.mainActorFunction

        #expect(throws: MainActorClosureFailure.rejected) {
            try function(1)
        }
    }
}
