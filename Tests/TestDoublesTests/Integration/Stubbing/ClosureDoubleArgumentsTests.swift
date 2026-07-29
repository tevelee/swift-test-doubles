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
}
