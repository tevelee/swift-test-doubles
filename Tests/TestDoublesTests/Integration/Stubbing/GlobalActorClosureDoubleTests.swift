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

    @MainActor
    @Test func remainingEffectfulViewsPreserveMainActorIsolation() async throws {
        let throwing =
            MainActorThrowingClosureDouble<Int, String>()
        throwing.whenAny().thenReturn("throwing")
        let throwingFunction: @MainActor @Sendable (Int) throws -> String =
            throwing.mainActorFunction
        #expect(try throwingFunction(1) == "throwing")

        let asyncThrowing =
            MainActorAsyncThrowingClosureDouble<Int, String>()
        asyncThrowing.whenAny().thenReturn("async-throwing")
        let asyncThrowingFunction: @MainActor @Sendable (Int) async throws -> String =
            asyncThrowing.mainActorFunction
        #expect(try await asyncThrowingFunction(2) == "async-throwing")

        let asyncTyped =
            MainActorAsyncTypedThrowingClosureDouble<
                Int,
                String,
                MainActorClosureFailure
            >()
        asyncTyped.whenAny().thenReturn("async-typed")
        let asyncTypedFunction:
            @MainActor @Sendable (
                Int
            ) async throws(MainActorClosureFailure) -> String =
                asyncTyped.mainActorFunction
        #expect(try await asyncTypedFunction(3) == "async-typed")
    }
}
