import Testing
@testable import TestDoubles
import TestDoublesFixtures

protocol MatcherService {
    func find(id: Int) -> String
    func search(query: String, limit: Int) -> [String]
}

struct RealMatcherService: MatcherService {
    func find(id: Int) -> String { "" }
    func search(query: String, limit: Int) -> [String] { [] }
}

final class MatcherReferenceBox {
    let value: Int

    init(value: Int) {
        self.value = value
    }
}

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

@Suite struct MatcherTests {
    @Test func matchingSupportsDefaultAndNamedDescriptions() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.search(query: matching(where: { $0.hasPrefix("test") }), limit: any()) }
            .thenReturn(["test"])
        stub.when {
            $0.search(
                query: matching(description: "admin", where: { $0.hasPrefix("admin") }),
                limit: any()
            )
        }
        .thenReturn(["admin"])
        stub.when { $0.search(query: any(), limit: any()) }.thenReturn([])

        #expect(stub().search(query: "test.users", limit: 10) == ["test"])
        #expect(stub().search(query: "admin.users", limit: 10) == ["admin"])
        #expect(stub().search(query: "public.users", limit: 10).isEmpty)
    }

    @Test func firstMatchingRegistrationWins() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: equal(42)) }.thenReturn("exact")
        stub.when { $0.find(id: any()) }.thenReturn("fallback")

        #expect(stub().find(id: 42) == "exact")
        #expect(stub().find(id: 1) == "fallback")
    }

    @Test func catchAllRegisteredFirstShadowsLaterMatchers() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: any()) }.thenReturn("fallback")
        stub.when { $0.find(id: equal(42)) }.thenReturn("exact")

        #expect(stub().find(id: 42) == "fallback")
        #expect(stub().find(id: 1) == "fallback")
    }

    @Test func reRegisteringAMatcherKeepsTheFirstBehavior() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: any()) }.thenReturn("guest")
        stub.when { $0.find(id: any()) }.thenReturn("admin")

        #expect(stub().find(id: 1) == "guest")
    }

    @Test func overlappingPredicatesResolveToFirstRegistration() throws {
        let stub = try Stub<any MatcherService>()
        stub.when {
            $0.find(id: matching(description: "six", where: { $0 == 6 }))
        }.thenReturn("six")
        stub.when {
            $0.find(id: matching(description: "even", where: { $0 % 2 == 0 }))
        }.thenReturn("even")

        #expect(stub().find(id: 6) == "six")
        #expect(stub().find(id: 4) == "even")
    }

    @Test func captorCollectsValuesDuringVerification() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: any()) }.thenReturn("X")
        let service: any MatcherService = stub()
        _ = service.find(id: 7)
        _ = service.find(id: 13)

        let ids = ArgumentCaptor<Int>()
        stub.verify(.exactly(2)) { $0.find(id: ids.capture()) }

        #expect(ids.values == [7, 13])
        #expect(ids.first == 7)
        #expect(ids.last == 13)
        ids.reset()
        #expect(ids.values.isEmpty)
    }

    @Test func captorCommitsOnlyAfterEveryArgumentMatches() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.search(query: any(), limit: any()) }.thenReturn([])
        let service: any MatcherService = stub()
        _ = service.search(query: "rejected", limit: 1)
        _ = service.search(query: "accepted", limit: 2)

        let queries = ArgumentCaptor<String>()
        stub.verify(.exactly(1)) {
            $0.search(query: queries.capture(), limit: equal(2))
        }

        #expect(queries.values == ["accepted"])
    }

    @Test func explicitReferencePlaceholdersSupportAnyAndMatching() throws {
        let stub = try Stub<any MatcherPlaceholderService>(
            .method(MatcherReferenceBox.self, returning: String.self),
            .method((any MatcherExistentialValue).self, returning: String.self)
        )
        let placeholder = MatcherReferenceBox(value: 0)
        stub.when {
            $0.inspect(
                reference: matching(
                    using: placeholder,
                    description: "positive",
                    where: { $0.value > 0 }
                )
            )
        }.thenReturn("positive")
        stub.when { $0.inspect(reference: any(using: placeholder)) }.thenReturn("any")

        #expect(stub().inspect(reference: MatcherReferenceBox(value: 2)) == "positive")
        #expect(stub().inspect(reference: MatcherReferenceBox(value: -1)) == "any")
    }

    @Test func explicitExistentialPlaceholderSupportsCapture() throws {
        let stub = try Stub<any MatcherPlaceholderService>(
            .method(MatcherReferenceBox.self, returning: String.self),
            .method((any MatcherExistentialValue).self, returning: String.self)
        )
        let placeholder: any MatcherExistentialValue = FirstMatcherExistentialValue(value: 0)
        stub.when { $0.inspect(existential: any(using: placeholder)) }.thenReturn("matched")
        let service: any MatcherPlaceholderService = stub()
        let actual: any MatcherExistentialValue = SecondMatcherExistentialValue(value: 42)

        #expect(service.inspect(existential: actual) == "matched")

        let values = ArgumentCaptor<any MatcherExistentialValue>()
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
        @Test func synthesizedReferencePlaceholderFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let _: MatcherReferenceBox = any()
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(
                diagnostic.contains(
                    "any() cannot safely synthesize a placeholder"
                )
            )
            #expect(diagnostic.contains("any(using:)"))
        }
    }
#endif

@Suite struct TypedThenTests {
    @Test func zeroOneAndTwoArgumentHandlers() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: any()) }.then { (id: Int) in "user_\(id)" }
        stub.when { $0.search(query: any(), limit: any()) }.then {
            (query: String, limit: Int) in
            Array(repeating: query, count: limit)
        }

        #expect(stub().find(id: 42) == "user_42")
        #expect(stub().search(query: "x", limit: 3) == ["x", "x", "x"])
    }

    @Test func typedThrowingHandlerPropagates() throws {
        struct ReadError: Error, Equatable { let path: String }
        let stub = try Stub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { (path: String) throws in
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
