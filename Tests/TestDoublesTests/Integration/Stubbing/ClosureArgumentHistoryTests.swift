import TestDoubles
import Testing

@Suite struct ClosureArgumentHistoryTests {
    @Test func mapsRecordedArgumentsWithoutTupleIndexing() {
        let double = ClosureDouble<(Int, String), Void>()
        let calls = double.whenAny()
        calls.thenDoNothing()

        double.invoke(1, "one")
        double.invoke(2, "two")

        let history = calls.argumentHistory()
        #expect(history.count == 2)
        #expect(
            history.map { number, label in
                "\(number)-\(label)"
            } == ["1-one", "2-two"]
        )
    }

    @Test func supportsIterationAndReduction() async {
        let double = AsyncClosureDouble<(Int, Bool), String>()
        double.whenAny().thenArguments { value, enabled in
            "\(value)-\(enabled)"
        }

        _ = await double.invoke(2, true)
        _ = await double.invoke(3, false)

        let history = double.argumentHistory()
        var visited: [Int] = []
        history.forEach { value, enabled in
            if enabled {
                visited.append(value)
            }
        }

        #expect(visited == [2])
        #expect(
            history.reduce(0) { total, value, _ in
                total + value
            } == 5
        )
    }
}
