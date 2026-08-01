import IssueReporting
import Testing
@testable import TestDoubles
import TestDoublesFixtures

protocol MatcherService {
    func find(id: Int) -> String
    func search(query: String, limit: Int) -> [String]
    func resolve(_ value: SameDescriptionMatcherValue) -> String
}

struct RealMatcherService: MatcherService {
    func find(id: Int) -> String { "" }
    func search(query: String, limit: Int) -> [String] { [] }
    func resolve(_ value: SameDescriptionMatcherValue) -> String { "" }
}

struct SameDescriptionMatcherValue: Equatable, CustomStringConvertible {
    let rawValue: Int

    var description: String { "value" }
}

final class MatcherReferenceBox {
    let value: Int

    init(value: Int) {
        self.value = value
    }
}

final class MatcherUnsupportedResultValue {}

final class MatcherUnsupportedResultFailure: Error {}

protocol MatcherExistentialValue {
    var value: Int { get }
}

struct FirstMatcherExistentialValue: MatcherExistentialValue {
    let value: Int
}

struct SecondMatcherExistentialValue: MatcherExistentialValue {
    let value: Int
}

protocol MatcherPlaceholderService {
    func inspect(reference: MatcherReferenceBox) -> String
    func inspect(existential: any MatcherExistentialValue) -> String
}

protocol OptionalMatcherPlaceholderService {
    func inspect(reference: MatcherReferenceBox?) -> String
    func inspect(nestedReference: MatcherReferenceBox??) -> String
}

@Suite struct MatcherTests {
    @Test func matchingSupportsDefaultAndNamedDescriptions() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.search(query: Match.matching(where: { $0.hasPrefix("test") }), limit: Match.any()) }
            .thenReturn(["test"])
        stub.when {
            $0.search(
                query: Match.matching(description: "admin", where: { $0.hasPrefix("admin") }),
                limit: Match.any()
            )
        }
        .thenReturn(["admin"])
        stub.when { $0.search(query: Match.any(), limit: Match.any()) }.thenReturn([])

        #expect(stub().search(query: "test.users", limit: 10) == ["test"])
        #expect(stub().search(query: "admin.users", limit: 10) == ["admin"])
        #expect(stub().search(query: "public.users", limit: 10).isEmpty)
    }

    @Test func firstMatchingRegistrationWins() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: Match.equal(42)) }.thenReturn("exact")
        stub.when { $0.find(id: Match.any()) }.thenReturn("fallback")

        #expect(stub().find(id: 42) == "exact")
        #expect(stub().find(id: 1) == "fallback")
    }

    @Test func literalEquatableValuesUseEqualityInsteadOfTheirDescription() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.resolve(SameDescriptionMatcherValue(rawValue: 1)) }.thenReturn("first")
        stub.when { $0.resolve(SameDescriptionMatcherValue(rawValue: 2)) }.thenReturn("second")

        #expect(stub().resolve(SameDescriptionMatcherValue(rawValue: 2)) == "second")
    }

    @Test func literalReferenceValuesUseIdentityInsteadOfTheirDescription() throws {
        let stub = try Stub<any MatcherPlaceholderService>(
            .method(MatcherReferenceBox.self, returning: String.self),
            .method((any MatcherExistentialValue).self, returning: String.self)
        )
        let first = MatcherReferenceBox(value: 1)
        let second = MatcherReferenceBox(value: 1)
        stub.when { $0.inspect(reference: first) }.thenReturn("first")
        stub.when { $0.inspect(reference: second) }.thenReturn("second")

        #expect(stub().inspect(reference: second) == "second")
    }

    @Test func literalOptionalReferenceValuesUseIdentityAndMatchNil() throws {
        let stub = try Stub<any OptionalMatcherPlaceholderService>(
            .method(MatcherReferenceBox?.self, returning: String.self),
            .method(MatcherReferenceBox??.self, returning: String.self)
        )
        let first: MatcherReferenceBox? = MatcherReferenceBox(value: 1)
        let second: MatcherReferenceBox? = MatcherReferenceBox(value: 1)
        let noReference: MatcherReferenceBox? = nil
        stub.when { $0.inspect(reference: first) }.thenReturn("first")
        stub.when { $0.inspect(reference: second) }.thenReturn("second")
        stub.when { $0.inspect(reference: noReference) }.thenReturn("nil")

        #expect(stub().inspect(reference: second) == "second")
        #expect(stub().inspect(reference: nil) == "nil")
    }

    @Test func literalNestedOptionalReferencesPreserveNilDepthAndIdentity() throws {
        let stub = try Stub<any OptionalMatcherPlaceholderService>(
            .method(MatcherReferenceBox?.self, returning: String.self),
            .method(MatcherReferenceBox??.self, returning: String.self)
        )
        let first: MatcherReferenceBox?? = .some(.some(MatcherReferenceBox(value: 1)))
        let second: MatcherReferenceBox?? = .some(.some(MatcherReferenceBox(value: 1)))
        let innerNil: MatcherReferenceBox?? = .some(nil)
        let outerNil: MatcherReferenceBox?? = nil
        stub.when { $0.inspect(nestedReference: first) }.thenReturn("first")
        stub.when { $0.inspect(nestedReference: second) }.thenReturn("second")
        stub.when { $0.inspect(nestedReference: innerNil) }.thenReturn("inner nil")
        stub.when { $0.inspect(nestedReference: outerNil) }.thenReturn("outer nil")

        #expect(stub().inspect(nestedReference: second) == "second")
        #expect(stub().inspect(nestedReference: .some(nil)) == "inner nil")
        #expect(stub().inspect(nestedReference: nil) == "outer nil")
    }

    @Test func catchAllRegisteredFirstShadowsLaterMatchers() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: Match.any()) }.thenReturn("fallback")
        // The catch-all shadows this specific registration, which is reported
        // at the when site in addition to the runtime first-match-wins result.
        expectReportsIssue {
            stub.when { $0.find(id: Match.equal(42)) }.thenReturn("exact")
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }

        #expect(stub().find(id: 42) == "fallback")
        #expect(stub().find(id: 1) == "fallback")
    }

    @Test func reRegisteringAMatcherKeepsTheFirstBehavior() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: Match.any()) }.thenReturn("guest")
        // A second identical registration is unreachable, reported at the
        // when site.
        expectReportsIssue {
            stub.when { $0.find(id: Match.any()) }.thenReturn("admin")
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }

        #expect(stub().find(id: 1) == "guest")
    }

    @Test func overlappingPredicatesResolveToFirstRegistration() throws {
        let stub = try Stub<any MatcherService>()
        stub.when {
            $0.find(id: Match.matching(description: "six", where: { $0 == 6 }))
        }.thenReturn("six")
        stub.when {
            $0.find(id: Match.matching(description: "even", where: { $0 % 2 == 0 }))
        }.thenReturn("even")

        #expect(stub().find(id: 6) == "six")
        #expect(stub().find(id: 4) == "even")
    }

    @Test func captorCollectsValuesDuringVerification() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: Match.any()) }.thenReturn("X")
        let service: any MatcherService = stub()
        _ = service.find(id: 7)
        _ = service.find(id: 13)

        let ids = Match.Capture<Int>()
        stub.verify(.exactly(2)) { $0.find(id: ids.capture()) }

        #expect(ids.values == [7, 13])
        #expect(ids.first == 7)
        #expect(ids.last == 13)
        ids.reset()
        #expect(ids.values.isEmpty)
    }

    @Test func captorCommitsOnlyAfterEveryArgumentMatches() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.search(query: Match.any(), limit: Match.any()) }.thenReturn([])
        let service: any MatcherService = stub()
        _ = service.search(query: "rejected", limit: 1)
        _ = service.search(query: "accepted", limit: 2)

        let queries = Match.Capture<String>()
        stub.verify(.exactly(1)) {
            $0.search(query: queries.capture(), limit: Match.equal(2))
        }

        #expect(queries.values == ["accepted"])
    }

    @Test func dispatchCaptorsPreserveArgumentAndCallOrder() throws {
        let stub = try Stub<any MatcherService>()
        let queries = Match.Capture<String>()
        let limits = Match.Capture<Int>()
        stub.when {
            $0.search(query: queries.capture(), limit: limits.capture())
        }.thenReturn([])

        _ = stub().search(query: "first", limit: 1)
        _ = stub().search(query: "second", limit: 2)

        #expect(queries.values == ["first", "second"])
        #expect(limits.values == [1, 2])
    }

    @Test func preparedProjectionDoesNotRepeatProjectionToCommitCapture() throws {
        let projections = LockedCounter()
        let counts = Match.Capture<Int>()
        let matcher = ProjectionMatcher(
            label: "count",
            matchers: [CaptureMatcher(capture: counts)]
        ) { value in
            projections.increment()
            return (value as? [Int])?.count
        }

        let transaction = try #require(
            StubBehaviorRegistry.prepareArgumentsMatch(
                [[1, 2, 3]],
                against: [matcher]
            )
        )
        transaction.commitCaptures()

        #expect(projections.value == 1)
        #expect(counts.values == [3])
    }

    @Test func explicitReferencePlaceholdersSupportAnyAndMatching() throws {
        let stub = try Stub<any MatcherPlaceholderService>(
            .method(MatcherReferenceBox.self, returning: String.self),
            .method((any MatcherExistentialValue).self, returning: String.self)
        )
        let placeholder = MatcherReferenceBox(value: 0)
        stub.when {
            $0.inspect(
                reference: Match.matching(
                    using: placeholder,
                    description: "positive",
                    where: { $0.value > 0 }
                )
            )
        }.thenReturn("positive")
        stub.when { $0.inspect(reference: Match.any(using: placeholder)) }.thenReturn("any")

        #expect(stub().inspect(reference: MatcherReferenceBox(value: 2)) == "positive")
        #expect(stub().inspect(reference: MatcherReferenceBox(value: -1)) == "any")
    }

    @Test func explicitExistentialPlaceholderSupportsCapture() throws {
        let stub = try Stub<any MatcherPlaceholderService>(
            .method(MatcherReferenceBox.self, returning: String.self),
            .method((any MatcherExistentialValue).self, returning: String.self)
        )
        let placeholder: any MatcherExistentialValue = FirstMatcherExistentialValue(value: 0)
        stub.when { $0.inspect(existential: Match.any(using: placeholder)) }.thenReturn("matched")
        let service: any MatcherPlaceholderService = stub()
        let actual: any MatcherExistentialValue = SecondMatcherExistentialValue(value: 42)

        #expect(service.inspect(existential: actual) == "matched")

        let values = Match.Capture<any MatcherExistentialValue>()
        stub.verify {
            $0.inspect(existential: values.capture(using: placeholder))
        }
        #expect(values.values.count == 1)
        #expect(values.first?.value == 42)
        #expect(values.first is SecondMatcherExistentialValue)
    }

}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct MatcherExitTests {
        @Test func mixedLiteralAndMatcherRecordingFailsBeforeRegistration() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any MatcherService>()
                _ = stub.when {
                    $0.search(query: "literal", limit: Match.any())
                }
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("Use either literals for every argument"))
            #expect(diagnostic.contains("Match.equal(_:)"))
        }

        @Test func literalClosureRecordingFailsWithMatcherGuidance() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = literalMatcher(for: {})
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("has no generic equality"))
            #expect(diagnostic.contains("Match.any(using:)"))
        }

        @Test func synthesizedReferencePlaceholderFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let _: MatcherReferenceBox = Match.any()
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(
                diagnostic.contains(
                    "Match.any() cannot safely synthesize a placeholder"
                )
            )
            #expect(diagnostic.contains("Match.any(using:)"))
        }

        @Test func synthesizedResultPlaceholderPreservesTheDiagnostic() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let _:
                    Result<
                        MatcherUnsupportedResultValue,
                        MatcherUnsupportedResultFailure
                    > = Match.any()
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(
                diagnostic.contains(
                    "Match.any() cannot safely synthesize a placeholder"
                )
            )
            #expect(diagnostic.contains("Match.any(using:)"))
        }
    }
#endif

@Suite struct TypedThenTests {
    @Test func zeroOneAndTwoArgumentHandlers() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: Match.any()) }.then { (id: Int) in "user_\(id)" }
        stub.when { $0.search(query: Match.any(), limit: Match.any()) }.then {
            (query: String, limit: Int) in
            Array(repeating: query, count: limit)
        }

        #expect(stub().find(id: 42) == "user_42")
        #expect(stub().search(query: "x", limit: 3) == ["x", "x", "x"])
    }

    @Test func typedThrowingHandlerPropagates() throws {
        struct ReadError: Error, Equatable { let path: String }
        let stub = try Stub<any ThrowingFileService>()
        stub.when { try $0.read(path: Match.any()) }.then { (path: String) throws in
            if path == "/missing" { throw ReadError(path: path) }
            return "content:\(path)"
        }

        #expect(try stub().read(path: "/ok") == "content:/ok")
        let error = #expect(throws: ReadError.self) {
            try stub().read(path: "/missing")
        }
        #expect(error?.path == "/missing")
    }
}
