import Testing
import TestDoubles

protocol Ledger {
    func classify(amount: Int) -> String
    func lookup(id: Int?) -> String
    func attach(node: LedgerNode) -> Bool
}

struct RealLedger: Ledger {
    func classify(amount: Int) -> String { "" }
    func lookup(id: Int?) -> String { "" }
    func attach(node: LedgerNode) -> Bool { false }
}

final class LedgerNode {}

@Suite struct RichMatchersTests {
    @Test func comparisonMatchers() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.classify(amount: atMost(0)) }.thenReturn("nonpositive")
        stub.when { $0.classify(amount: inRange(1 ..< 100)) }.thenReturn("small")
        stub.when { $0.classify(amount: greaterThan(99)) }.thenReturn("large")

        let ledger: any Ledger = stub()
        #expect(ledger.classify(amount: -5) == "nonpositive")
        #expect(ledger.classify(amount: 0) == "nonpositive")
        #expect(ledger.classify(amount: 1) == "small")
        #expect(ledger.classify(amount: 99) == "small")
        #expect(ledger.classify(amount: 100) == "large")
    }

    @Test func closedRangeAndAtLeastLessThan() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.classify(amount: inRange(10 ... 20)) }.thenReturn("mid")
        stub.when { $0.classify(amount: lessThan(10)) }.thenReturn("low")
        stub.when { $0.classify(amount: atLeast(21)) }.thenReturn("high")

        let ledger: any Ledger = stub()
        #expect(ledger.classify(amount: 9) == "low")
        #expect(ledger.classify(amount: 10) == "mid")
        #expect(ledger.classify(amount: 20) == "mid")
        #expect(ledger.classify(amount: 21) == "high")
    }

    @Test func negationAndInequality() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.classify(amount: notEqual(0)) }.thenReturn("nonzero")
        stub.when { $0.classify(amount: not(greaterThan(0))) }.thenReturn("zero-or-less")

        let ledger: any Ledger = stub()
        #expect(ledger.classify(amount: 7) == "nonzero")
        #expect(ledger.classify(amount: -3) == "nonzero")
        #expect(ledger.classify(amount: 0) == "zero-or-less")
    }

    @Test func conjunctionDisjunctionAndOneOf() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.classify(amount: allOf(greaterThan(0), lessThan(10))) }
            .thenReturn("single-digit")
        stub.when { $0.classify(amount: oneOf(10, 20, 30)) }.thenReturn("round")
        stub.when { $0.classify(amount: anyOf(equal(-1), lessThan(-100))) }
            .thenReturn("edge")
        stub.when { $0.classify(amount: any()) }.thenReturn("other")

        let ledger: any Ledger = stub()
        #expect(ledger.classify(amount: 5) == "single-digit")
        #expect(ledger.classify(amount: 10) == "round")
        #expect(ledger.classify(amount: 20) == "round")
        #expect(ledger.classify(amount: -1) == "edge")
        #expect(ledger.classify(amount: -200) == "edge")
        #expect(ledger.classify(amount: 42) == "other")
    }

    @Test func optionalMatchers() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.lookup(id: isNil()) }.thenReturn("missing")
        stub.when { $0.lookup(id: some(greaterThan(0))) }.thenReturn("positive")
        stub.when { $0.lookup(id: notNil()) }.thenReturn("present")

        let ledger: any Ledger = stub()
        #expect(ledger.lookup(id: nil) == "missing")
        #expect(ledger.lookup(id: 5) == "positive")
        #expect(ledger.lookup(id: -5) == "present")
    }

    @Test func identityMatcher() throws {
        let stub = try Stub<any Ledger>()
        let tracked = LedgerNode()
        stub.when { $0.attach(node: identical(to: tracked)) }.thenReturn(true)
        stub.when { $0.attach(node: any(using: tracked)) }.thenReturn(false)

        let ledger: any Ledger = stub()
        #expect(ledger.attach(node: tracked) == true)
        #expect(ledger.attach(node: LedgerNode()) == false)
    }

    @Test func captureComposedWithConstraint() throws {
        let stub = try Stub<any Ledger>()
        let positives = ArgumentCaptor<Int>()
        stub.when { $0.classify(amount: allOf(positives.capture(), greaterThan(0))) }
            .thenReturn("positive")
        stub.when { $0.classify(amount: any()) }.thenReturn("other")

        let ledger: any Ledger = stub()
        #expect(ledger.classify(amount: 3) == "positive")
        #expect(ledger.classify(amount: -1) == "other")
        #expect(ledger.classify(amount: 8) == "positive")

        // Only the values that satisfied the whole `allOf` are captured.
        #expect(positives.values == [3, 8])
    }

    @Test func anyOfPredicateIsEvaluatedOnceWhenDispatchCommits() throws {
        let stub = try Stub<any Ledger>()
        let evaluations = LockedCounter()
        stub.when {
            $0.classify(
                amount: anyOf(
                    matching(
                        description: "positive",
                        where: { value in
                            evaluations.increment()
                            return value > 0
                        }),
                    equal(0)
                )
            )
        }.thenReturn("matched")

        #expect(stub().classify(amount: 7) == "matched")
        #expect(evaluations.value == 1)
    }

    @Test func anyOfPredicateIsEvaluatedOnceWhenVerificationCommits() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.classify(amount: any()) }.thenReturn("matched")
        _ = stub().classify(amount: 7)
        let evaluations = LockedCounter()

        stub.verify {
            $0.classify(
                amount: anyOf(
                    matching(
                        description: "positive",
                        where: { value in
                            evaluations.increment()
                            return value > 0
                        }),
                    equal(0)
                )
            )
        }

        #expect(evaluations.value == 1)
    }

    @Test func verificationUsesRichMatchers() throws {
        let stub = try Stub<any Ledger>()
        stub.when { $0.classify(amount: any()) }.thenReturn("x")

        let ledger: any Ledger = stub()
        _ = ledger.classify(amount: 5)
        _ = ledger.classify(amount: 50)
        _ = ledger.classify(amount: -5)

        stub.verify(.exactly(2)) { $0.classify(amount: greaterThan(0)) }
        stub.verify(.exactly(1)) { $0.classify(amount: lessThan(0)) }
        stub.verify(.exactly(1)) { $0.classify(amount: inRange(0 ... 10)) }
        stub.verify(.never()) { $0.classify(amount: oneOf(1, 2, 3)) }
    }
}

protocol TagIndex {
    func matchScores(_ scores: [Int]) -> String
    func matchTags(_ tags: [String]) -> String
    func matchName(_ name: String) -> String
}

struct RealTagIndex: TagIndex {
    func matchScores(_ scores: [Int]) -> String { "" }
    func matchTags(_ tags: [String]) -> String { "" }
    func matchName(_ name: String) -> String { "" }
}

@Suite struct CollectionMatchersTests {
    @Test func emptinessAndCount() throws {
        let stub = try Stub<any TagIndex>()
        stub.when { $0.matchScores(isEmpty()) }.thenReturn("empty")
        stub.when { $0.matchScores(hasCount(2)) }.thenReturn("pair")
        stub.when { $0.matchScores(hasCount(matching: greaterThan(2))) }.thenReturn("many")
        stub.when { $0.matchScores(nonEmpty()) }.thenReturn("some")

        let index: any TagIndex = stub()
        #expect(index.matchScores([]) == "empty")
        #expect(index.matchScores([1, 2]) == "pair")
        #expect(index.matchScores([1, 2, 3, 4]) == "many")
        #expect(index.matchScores([9]) == "some")
    }

    @Test func membershipAndOrdering() throws {
        let stub = try Stub<any TagIndex>()
        stub.when { $0.matchScores(startsWith(1, 2)) }.thenReturn("prefixed")
        stub.when { $0.matchScores(endsWith(8, 9)) }.thenReturn("suffixed")
        stub.when { $0.matchScores(containsAll(3, 4)) }.thenReturn("superset")
        stub.when { $0.matchScores(contains(7)) }.thenReturn("has-seven")
        stub.when { $0.matchScores(contains { $0 < 0 }) }.thenReturn("has-negative")
        stub.when { $0.matchScores(any()) }.thenReturn("other")

        let index: any TagIndex = stub()
        #expect(index.matchScores([1, 2, 5]) == "prefixed")
        #expect(index.matchScores([5, 8, 9]) == "suffixed")
        #expect(index.matchScores([4, 3, 100]) == "superset")
        #expect(index.matchScores([100, 7]) == "has-seven")
        #expect(index.matchScores([100, -3]) == "has-negative")
        #expect(index.matchScores([100, 200]) == "other")
    }
}

@Suite struct StringMatchersTests {
    @Test func stringMatchers() throws {
        let stub = try Stub<any TagIndex>()
        stub.when { $0.matchName(hasPrefix("com.")) }.thenReturn("reverse-dns")
        stub.when { $0.matchName(hasSuffix(".swift")) }.thenReturn("source")
        stub.when { $0.matchName(containsSubstring("test")) }.thenReturn("test")
        stub.when { $0.matchName(equalsIgnoringCase("readme")) }.thenReturn("readme")
        stub.when { $0.matchName(matchesRegex("^[0-9]+$")) }.thenReturn("numeric")
        stub.when { $0.matchName(any()) }.thenReturn("other")

        let index: any TagIndex = stub()
        #expect(index.matchName("com.example.app") == "reverse-dns")
        #expect(index.matchName("Model.swift") == "source")
        #expect(index.matchName("my_test_file") == "test")
        #expect(index.matchName("README") == "readme")
        #expect(index.matchName("12345") == "numeric")
        #expect(index.matchName("plain") == "other")
    }
}
