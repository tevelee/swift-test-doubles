import TestDoubles
import Testing

private enum SendableClosureFailure: Error {
    case rejected
}

@Suite struct SendableClosureDoubleTests {
    @Test func synchronousFunctionCrossesADetachedTaskBoundary() async {
        let double = SendableClosureDouble<Int, String>()
        double.whenAny().then { "value-\($0)" }
        let function: @Sendable (Int) -> String = double.sendableFunction

        let result = await Task.detached {
            function(42)
        }.value

        #expect(result == "value-42")
        #expect(double.invocations == [42])
    }

    @Test func everyEffectCombinationProducesASendableFunction() async throws {
        let throwing = SendableThrowingClosureDouble<Int, String>()
        throwing.whenAny().thenReturn("throwing")
        let throwingFunction: @Sendable (Int) throws -> String =
            throwing.sendableFunction

        let asynchronous = SendableAsyncClosureDouble<Int, String>()
        asynchronous.whenAny().thenReturn("async")
        let asynchronousFunction: @Sendable (Int) async -> String =
            asynchronous.sendableFunction

        let asyncThrowing =
            SendableAsyncThrowingClosureDouble<Int, String>()
        asyncThrowing.when(equal: -1).thenThrow(
            SendableClosureFailure.rejected
        )
        asyncThrowing.whenAny().thenReturn("async-throwing")
        let asyncThrowingFunction: @Sendable (Int) async throws -> String =
            asyncThrowing.sendableFunction

        #expect(try throwingFunction(0) == "throwing")
        #expect(await asynchronousFunction(0) == "async")
        #expect(try await asyncThrowingFunction(0) == "async-throwing")
        await #expect(throws: SendableClosureFailure.self) {
            try await asyncThrowingFunction(-1)
        }
    }
}
