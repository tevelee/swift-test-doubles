import Testing
@testable import TestDoubles

@Suite struct StubBehaviorRegistryIndexTests {
    @Test func exactCandidatesPreserveOrderWithPredicateFallbacks() throws {
        var registry = StubBehaviorRegistry()
        registry.add(
            method: 0,
            matchers: [EqualMatcher(expected: 1)],
            diagnosticSignature: "literal one",
            behavior: .fixed(.success(1))
        )
        registry.add(
            method: 0,
            matchers: [
                PredicateMatcher<Int>(
                    description: "two",
                    predicate: { $0 == 2 }
                )
            ],
            diagnosticSignature: "predicate two",
            behavior: .fixed(.success(2))
        )
        registry.add(
            method: 0,
            matchers: [EqualMatcher(expected: 3)],
            diagnosticSignature: "literal three",
            behavior: .fixed(.success(3))
        )
        for value in 4 ... 5 {
            registry.add(
                method: 0,
                matchers: [EqualMatcher(expected: value)],
                diagnosticSignature: "literal \(value)",
                behavior: .fixed(.success(value))
            )
        }
        let snapshot = registry.snapshot(for: 0)
        let entries = try #require(snapshot.entries)

        #expect(snapshot.candidateEntryIndices(for: [1]) == [0, 1])
        #expect(snapshot.candidateEntryIndices(for: [2]) == [1])
        #expect(snapshot.candidateEntryIndices(for: [3]) == [1, 2])
        #expect(
            StubBehaviorRegistry.firstPreparedEntryMatch(
                for: [3],
                in: entries,
                candidateEntryIndices: snapshot.candidateEntryIndices(for: [3])
            )?.entryIndex == 2
        )
    }

    @Test func hashableEqualityMatchersUseTypedExactKeys() {
        var registry = StubBehaviorRegistry()
        registry.add(
            method: 0,
            matchers: [EqualMatcher(expected: 42)],
            diagnosticSignature: "equal 42",
            behavior: .fixed(.success(42))
        )
        for value in 43 ... 45 {
            registry.add(
                method: 0,
                matchers: [EqualMatcher(expected: value)],
                diagnosticSignature: "equal \(value)",
                behavior: .fixed(.success(value))
            )
        }
        let snapshot = registry.snapshot(for: 0)

        #expect(snapshot.candidateEntryIndices(for: [42]) == [0])
        #expect(snapshot.candidateEntryIndices(for: [43]) == [1])
        #expect(snapshot.candidateEntryIndices(for: [46]) == [])
        #expect(snapshot.candidateEntryIndices(for: ["42"]) == [])
    }
}
