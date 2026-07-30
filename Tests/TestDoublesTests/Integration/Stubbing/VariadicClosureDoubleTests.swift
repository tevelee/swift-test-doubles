import TestDoubles
import Testing

private enum VariadicClosureFailure: Error, Equatable {
    case empty
}

@Suite struct VariadicClosureDoubleTests {
    @Test func parameterPackAliasKeepsHeterogeneousArgumentsTyped() {
        let double =
            ParameterPackClosureDouble<Int, String, Bool>()
        double.whenArguments { (count: Int, label: String) in
            count > 0 && !label.isEmpty
        }.thenArguments { (count: Int, label: String) in
            label.count == count
        }

        let matches: (Int, String) -> Bool =
            double.expandedFunction()

        #expect(matches(3, "abc"))
        #expect(!matches(2, "abc"))
        let history = double.argumentHistory()
        #expect(
            history.map { count, label in "\(count):\(label)" } == [
                "3:abc", "2:abc"
            ])
    }

    @Test func synchronousDoubleRecordsEachVariadicInvocationAsAnArray() {
        let double = VariadicClosureDouble<Int, Int>()
        double.when { !$0.isEmpty }.then { $0.reduce(0, +) }
        double.when(equal: []).thenReturn(0)

        let sum: (Int...) -> Int = double.variadicFunction()

        #expect(sum(1, 2, 3) == 6)
        #expect(sum() == 0)
        #expect(double.invokeVariadic(4, 5) == 9)
        #expect(double.invocations == [[1, 2, 3], [], [4, 5]])
    }

    @Test func effectfulDoublesPreserveVariadicFunctionEffects() async throws {
        let throwing = VariadicThrowingClosureDouble<String, String>()
        throwing.whenAny().then { values in
            guard !values.isEmpty else {
                throw VariadicClosureFailure.empty
            }
            return values.joined(separator: "-")
        }
        let join: (String...) throws -> String =
            throwing.variadicFunction()
        #expect(try join("one", "two") == "one-two")
        #expect(throws: VariadicClosureFailure.empty) {
            _ = try join()
        }

        let asynchronous = VariadicAsyncClosureDouble<Int, Int>()
        asynchronous.whenAny().then { values in
            await Task.yield()
            return values.reduce(0, +)
        }
        let sum: (Int...) async -> Int =
            asynchronous.variadicFunction()
        #expect(await sum(2, 3, 4) == 9)

        let asyncThrowing =
            VariadicAsyncThrowingClosureDouble<Int, Int>()
        asyncThrowing.whenAny().then { values in
            await Task.yield()
            guard !values.isEmpty else {
                throw VariadicClosureFailure.empty
            }
            return values.count
        }
        let count: (Int...) async throws -> Int =
            asyncThrowing.variadicFunction()
        #expect(try await count(1, 2) == 2)
        await #expect(throws: VariadicClosureFailure.empty) {
            _ = try await count()
        }
    }

    @Test func typedThrowsDoublesRetainTheirPreciseFailureType() async throws {
        let synchronous =
            VariadicTypedThrowingClosureDouble<
                Int,
                Int,
                VariadicClosureFailure
            >()
        synchronous.whenAny().then { values in
            guard let first = values.first else {
                throw VariadicClosureFailure.empty
            }
            return first
        }
        let first: (Int...) throws(VariadicClosureFailure) -> Int =
            synchronous.variadicFunction()
        #expect(try first(7, 8) == 7)
        #expect(throws: VariadicClosureFailure.empty) {
            _ = try first()
        }

        let asynchronous =
            VariadicAsyncTypedThrowingClosureDouble<
                Int,
                Int,
                VariadicClosureFailure
            >()
        asynchronous.whenAny().then { values in
            guard let last = values.last else {
                throw VariadicClosureFailure.empty
            }
            return last
        }
        let last: (Int...) async throws(VariadicClosureFailure) -> Int =
            asynchronous.variadicFunction()
        #expect(try await last(7, 8) == 8)
        await #expect(throws: VariadicClosureFailure.empty) {
            _ = try await last()
        }
    }
}
