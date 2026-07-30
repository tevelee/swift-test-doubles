import TestDoubles
import Testing

private enum ImmediateCallbackFailure: Error, Equatable {
    case rejected(Int)
}

@Suite struct NonescapingCallbackRecorderTests {
    @Test func recordsACompilerCheckedNonescapingCallback() {
        let recorder =
            NonescapingCallbackRecorder<Int, String>()

        func dependency(
            value: Int,
            callback: (Int) -> String
        ) -> String {
            recorder.invoke(callback, with: value)
        }

        #expect(
            dependency(value: 3) { "value-\($0)" }
                == "value-3"
        )
        #expect(recorder.invocations == [3])
        #expect(recorder.results == ["value-3"])
        #expect(recorder.errors.isEmpty)
    }

    @Test func preservesTypedThrowsWithoutRetainingTheCallback() {
        let recorder =
            NonescapingCallbackRecorder<Int, String>()

        func dependency(
            value: Int,
            callback:
                (Int) throws(ImmediateCallbackFailure) -> String
        ) throws(ImmediateCallbackFailure) -> String {
            try recorder.invoke(callback, with: value)
        }

        let callback: (Int) throws(ImmediateCallbackFailure) -> String =
            { value throws(ImmediateCallbackFailure) in
                guard value >= 0 else {
                    throw .rejected(value)
                }
                return "\(value)"
            }
        #expect(throws: ImmediateCallbackFailure.rejected(-1)) {
            try dependency(value: -1, callback: callback)
        }
        #expect(recorder.invocations == [-1])
        #expect(recorder.results.isEmpty)
        #expect(recorder.errors.count == 1)
    }

    @Test func voidCallbacksCanBeInvokedForSeveralValues() {
        let recorder =
            NonescapingCallbackRecorder<Int, Void>()
        var received: [Int] = []

        recorder.invoke(
            { received.append($0) },
            with: 1,
            2,
            3
        )

        #expect(received == [1, 2, 3])
        #expect(recorder.invocations == [1, 2, 3])
        #expect(recorder.callCount == 3)
    }
}
