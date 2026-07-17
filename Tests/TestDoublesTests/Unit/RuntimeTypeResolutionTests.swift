import Testing
@testable import TestDoubles
import TestDoublesFixtures

struct ResolutionElementValue: Equatable, Hashable, Sendable {
    let id: Int
}

/// Unit coverage for demangled-name resolution: no stubs are constructed and
/// no witness tables are involved.
@Suite struct RuntimeTypeResolutionTests {
    @Test func bracketSugarResolvesArbitraryElements() {
        #expect(resolveRuntimeType("[Swift.UInt8]") == [UInt8].self)
        #expect(resolveRuntimeType("[[Swift.Int]]") == [[Int]].self)
        #expect(resolveRuntimeType("[Swift.String]") == [String].self)
    }

    @Test func bracketSugarResolvesDictionaries() {
        #expect(resolveRuntimeType("[Swift.String : Swift.Int]") == [String: Int].self)
        #expect(resolveRuntimeType("[Swift.Int: [Swift.String]]") == [Int: [String]].self)
    }

    @Test func constructorSpellingsResolveSetsAndDictionaries() {
        #expect(resolveRuntimeType("Swift.Set<Swift.String>") == Set<String>.self)
        #expect(resolveRuntimeType("Set<Swift.Int>") == Set<Int>.self)
        #expect(
            resolveRuntimeType("Swift.Dictionary<Swift.String, Swift.Int>")
                == [String: Int].self
        )
    }

    @Test func nonHashableKeysFailResolutionSafely() {
        #expect(resolveRuntimeType("[(Swift.Int, Swift.Int) : Swift.Int]") == nil)
    }

    @Test func demangledFunctionSpellingsResolveCanonicalMetadata() {
        #expect(
            resolveRuntimeType("(Swift.Int) -> Swift.Int")
                == ((Int) -> Int).self
        )
        #expect(
            resolveRuntimeType("@Sendable (Swift.Int) -> Swift.Int")
                == (@Sendable (Int) -> Int).self
        )
        #expect(
            resolveRuntimeType("(Swift.Int, Swift.String) throws -> Swift.Bool")
                == ((Int, String) throws -> Bool).self
        )
        #expect(
            resolveRuntimeType("@Sendable (Swift.Int) async throws -> Swift.String")
                == (@Sendable (Int) async throws -> String).self
        )
    }

    @Test func genericResultsContainingClosureArrowsResolveCompletely() throws {
        typealias ClosureResult = Result<@Sendable (Int) -> String, Never>
        let spelling =
            "Swift.Result<@Sendable (Swift.Int) -> Swift.String, Swift.Never>"

        #expect(resolveRuntimeType(spelling) == ClosureResult.self)

        let signature = try #require(
            parseWitnessSignature(
                "method descriptor for Probe.transform(value: \(spelling)) -> \(spelling)",
                kind: .method
            )
        )
        #expect(signature.argumentTypeNames == [spelling])
        #expect(signature.returnTypeName == spelling)
    }

    @Test func publicGenericNominalsResolveFromTheirMetadataAccessor() {
        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalGenericClosureBox<Swift.Int>"
            ) == ExternalGenericClosureBox<Int>.self
        )
    }

    @Test func closurePointerAuthenticationMatchesSwiftStableHashes() throws {
        let discriminators = try #require(
            FunctionReabstraction.pointerAuthDiscriminators(
                for: (@Sendable (Int) -> Int).self
            )
        )

        #expect(discriminators.direct == 18_587)
        #expect(discriminators.generic == 55_683)
    }
}

/// Unit coverage for recording-placeholder synthesis.
@Suite struct PlaceholderSynthesisTests {
    @Test func placeholdersSynthesizeEmptyCollections() {
        #expect(PlaceholderValue.make([UInt8].self) == [])
        #expect(PlaceholderValue.make([ResolutionElementValue].self) == [])
        #expect(PlaceholderValue.make(Set<String>.self) == [])
        #expect(PlaceholderValue.make([String: Int].self) == [:])
        #expect(PlaceholderValue.make([ResolutionElementValue: [Int]].self) == [:])
    }
}
