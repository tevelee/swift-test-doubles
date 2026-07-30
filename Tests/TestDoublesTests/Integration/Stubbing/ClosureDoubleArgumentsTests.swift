import TestDoubles
import Testing

private enum ClosureArgumentsFailure: Error, Equatable {
    case rejected(Int)
}

@Suite struct ClosureDoubleArgumentsTests {
    @Test func synchronousDoubleExpandsManyTypedArguments() {
        // swiftlint:disable:next large_tuple
        typealias Arguments = (
            Int,
            String,
            Bool,
            Double,
            UInt,
            Character,
            Int8,
            Float
        )
        let double = ClosureDouble<Arguments, String>()
        let matching = double.whenArguments {
            (
                count: Int,
                label: String,
                enabled: Bool,
                ratio: Double,
                index: UInt,
                marker: Character,
                offset: Int8,
                scale: Float
            ) in
            count == 3 && label == "books" && enabled && ratio == 0.5
                && index == 4 && marker == "!" && offset == -2 && scale == 1.5
        }
        matching.thenArguments {
            count,
            label,
            enabled,
            ratio,
            index,
            marker,
            offset,
            scale in
            "\(count) \(label) \(enabled) \(ratio) \(index) \(marker) \(offset) \(scale)"
        }

        let function:
            (
                Int,
                String,
                Bool,
                Double,
                UInt,
                Character,
                Int8,
                Float
            ) -> String = double.expandedFunction()

        #expect(function(3, "books", true, 0.5, 4, "!", -2, 1.5) == "3 books true 0.5 4 ! -2 1.5")
        matching.verify()
        #expect(matching.arguments().first?.0 == 3)
        #expect(matching.arguments().first?.1 == "books")
    }

    @Test func throwingDoubleSupportsSeparateArgumentsAndComputedFailures() throws {
        let double = ThrowingClosureDouble<(Int, String), String>()
        double.whenArguments { (value: Int, _: String) in
            value > 0
        }.thenArguments { (value: Int, label: String) in
            guard value != 2 else {
                throw ClosureArgumentsFailure.rejected(value)
            }
            return "\(label)-\(value)"
        }

        let function: (Int, String) throws -> String = double.expandedFunction()
        #expect(try function(1, "item") == "item-1")
        #expect(throws: ClosureArgumentsFailure.rejected(2)) {
            _ = try function(2, "item")
        }
    }

    @Test func asynchronousDoubleSupportsSeparateArgumentsAndCallCounts() async {
        let double = AsyncClosureDouble<(Int, String, Bool), String>()
        double.whenAny().thenForEachCallArguments {
            (count: Int, value: Int, label: String, enabled: Bool) async in
            await Task.yield()
            return "\(count):\(value):\(label):\(enabled)"
        }

        let function: (Int, String, Bool) async -> String =
            double.expandedFunction()
        #expect(await function(1, "one", true) == "1:1:one:true")
        #expect(await double.invoke(2, "two", false) == "2:2:two:false")
    }

    @Test func asyncThrowingDoubleSupportsManyArgumentsAndEffects() async throws {
        let double = AsyncThrowingClosureDouble<
            (Int, Int, Int, Int, Int, Int),
            Int
        >()
        double.whenAny().thenArguments {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) async throws in
            await Task.yield()
            guard a >= 0 else {
                throw ClosureArgumentsFailure.rejected(a)
            }
            return a + b + c + d + e + f
        }

        let function: (Int, Int, Int, Int, Int, Int) async throws -> Int =
            double.expandedFunction()
        #expect(try await function(1, 2, 3, 4, 5, 6) == 21)
        await #expect(throws: ClosureArgumentsFailure.rejected(-1)) {
            _ = try await function(-1, 2, 3, 4, 5, 6)
        }
    }

    @Test func effectfulDoublesAdaptNullaryFunctions() async throws {
        let throwing = ThrowingClosureDouble<Void, String>()
        throwing.whenAny().thenThrow(ClosureArgumentsFailure.rejected(0))
        let throwingFunction: () throws -> String =
            throwing.expandedFunction()
        #expect(throws: ClosureArgumentsFailure.rejected(0)) {
            _ = try throwingFunction()
        }

        let asynchronous = AsyncClosureDouble<Void, String>()
        asynchronous.whenAny().thenReturn("ready")
        let asynchronousFunction: () async -> String =
            asynchronous.expandedFunction()
        #expect(await asynchronousFunction() == "ready")

        let asyncThrowing = AsyncThrowingClosureDouble<Void, String>()
        asyncThrowing.whenAny().thenReturn("loaded")
        let asyncThrowingFunction: () async throws -> String =
            asyncThrowing.expandedFunction()
        #expect(try await asyncThrowingFunction() == "loaded")
    }

    @Test func synchronousAdaptersCoverBoundedAndUnboundedBehaviors() throws {
        let bounded = ClosureDouble<(Int, Int), Int>()
        bounded.whenAny().thenArguments(times: 1) { $0 + $1 }
        #expect(bounded.invoke(1, 2) == 3)

        let counted = ClosureDouble<(Int, Int), Int>()
        counted.whenAny().thenForEachCallArguments(times: 1) {
            count,
            first,
            second in
            count + first + second
        }
        #expect(counted.invoke(1, 2) == 4)

        let repeatingCounted = ClosureDouble<(Int, Int), Int>()
        repeatingCounted.whenAny().thenForEachCallArguments(times: 1...) {
            count,
            first,
            second in
            count * (first + second)
        }
        #expect(repeatingCounted.invoke(2, 3) == 5)

        let throwing = ThrowingClosureDouble<(Int, Int), Int>()
        throwing.whenAny().thenArguments(times: 1) {
            (first: Int, second: Int) throws in
            first + second
        }
        #expect(try throwing.invoke(3, 4) == 7)

        let throwingCounted = ThrowingClosureDouble<(Int, Int), Int>()
        throwingCounted.whenAny().thenForEachCallArguments(times: 1) {
            (count: Int, first: Int, second: Int) throws in
            count + first + second
        }
        #expect(try throwingCounted.invoke(3, 4) == 8)

        let repeatingThrowingCounted =
            ThrowingClosureDouble<(Int, Int), Int>()
        repeatingThrowingCounted.whenAny().thenForEachCallArguments(
            times: 1...
        ) {
            (count: Int, first: Int, second: Int) throws in
            count * (first + second)
        }
        #expect(try repeatingThrowingCounted.invoke(3, 4) == 7)

        let typed =
            TypedThrowingClosureDouble<
                (Int, Int),
                Int,
                ClosureArgumentsFailure
            >()
        typed.whenAny().thenArguments { $0 + $1 }
        #expect(try typed.invoke(4, 5) == 9)
    }

    @Test func asynchronousAdaptersCoverEveryHandlerShape() async throws {
        let immediate = AsyncClosureDouble<(Int, Int), Int>()
        immediate.whenArguments { $0 > 0 && $1 > 0 }
            .thenArguments(times: 1) { $0 + $1 }
        #expect(await immediate.invoke(1, 2) == 3)

        let suspended = AsyncClosureDouble<(Int, Int), Int>()
        suspended.whenAny().thenArguments(times: 1) {
            (first: Int, second: Int) async in
            await Task.yield()
            return first + second
        }
        #expect(await suspended.invoke(2, 3) == 5)

        let repeatingSuspended = AsyncClosureDouble<(Int, Int), Int>()
        repeatingSuspended.whenAny().thenArguments(times: 1...) {
            (first: Int, second: Int) async in
            await Task.yield()
            return first * second
        }
        #expect(await repeatingSuspended.invoke(2, 3) == 6)

        let counted = AsyncClosureDouble<(Int, Int), Int>()
        counted.whenAny().thenForEachCallArguments(times: 1) {
            (count: Int, first: Int, second: Int) async in
            await Task.yield()
            return count + first + second
        }
        #expect(await counted.invoke(2, 3) == 6)

        let immediateThrowing =
            AsyncThrowingClosureDouble<(Int, Int), Int>()
        immediateThrowing.whenArguments { $0 > 0 && $1 > 0 }
            .thenArguments(times: 1) {
                (first: Int, second: Int) throws in
                first + second
            }
        #expect(try await immediateThrowing.invoke(3, 4) == 7)

        let suspendedThrowing =
            AsyncThrowingClosureDouble<(Int, Int), Int>()
        suspendedThrowing.whenAny().thenArguments(times: 1) {
            (first: Int, second: Int) async throws in
            await Task.yield()
            return first + second
        }
        #expect(try await suspendedThrowing.invoke(4, 5) == 9)

        let throwingCounted =
            AsyncThrowingClosureDouble<(Int, Int), Int>()
        throwingCounted.whenAny().thenForEachCallArguments(times: 1) {
            (count: Int, first: Int, second: Int) async throws in
            await Task.yield()
            return count + first + second
        }
        #expect(try await throwingCounted.invoke(4, 5) == 10)

        let repeatingThrowingCounted =
            AsyncThrowingClosureDouble<(Int, Int), Int>()
        repeatingThrowingCounted.whenAny().thenForEachCallArguments(
            times: 1...
        ) {
            (count: Int, first: Int, second: Int) async throws in
            await Task.yield()
            return count * (first + second)
        }
        #expect(try await repeatingThrowingCounted.invoke(4, 5) == 9)

        let typed =
            AsyncTypedThrowingClosureDouble<
                (Int, Int),
                Int,
                ClosureArgumentsFailure
            >()
        typed.whenArguments { $0 > 0 && $1 > 0 }
            .thenArguments { $0 + $1 }
        #expect(try await typed.invoke(5, 6) == 11)
    }
}
