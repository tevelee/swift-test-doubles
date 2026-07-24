import Testing
@testable import TestDoubles
import TestDoublesFixtures

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

    @Test func constructorSpellingsResolveSIMDVectors() {
        #expect(resolveRuntimeType("Swift.SIMD2<Swift.Float>") == SIMD2<Float>.self)
        #expect(resolveRuntimeType("SIMD4<Swift.Int32>") == SIMD4<Int32>.self)
        #expect(resolveRuntimeType("Swift.SIMD16<Swift.UInt8>") == SIMD16<UInt8>.self)
        #expect(resolveRuntimeType("Swift.SIMD3<Swift.Float>") == SIMD3<Float>.self)
        #expect(resolveRuntimeType("Swift.SIMD64<Swift.Int8>") == SIMD64<Int8>.self)
    }

    @Test func nonSIMDScalarElementsFailSIMDResolutionSafely() {
        #expect(resolveRuntimeType("Swift.SIMD2<Swift.String>") == nil)
    }

    @Test func tupleMetadataResolvesPastTheOldTwoOrThreeElementCap() {
        // td_swift_get_tuple_type_metadata used to wrap only
        // swift_getTupleTypeMetadata2/3, capping resolvable tuples at exactly
        // two or three elements. It now wraps the general
        // swift_getTupleTypeMetadata entry point directly, so any arity
        // resolves the same way.
        #expect(resolveRuntimeType("(Swift.Int, Swift.String)") == (Int, String).self)
        #expect(
            resolveRuntimeType("(Swift.Int, Swift.String, Swift.Bool)")
                == (Int, String, Bool).self
        )
        #expect(
            resolveRuntimeType("(Swift.Int, Swift.String, Swift.Bool, Swift.Double)")
                == (Int, String, Bool, Double).self
        )
        #expect(
            resolveRuntimeType(
                "(Swift.Int, Swift.String, Swift.Bool, Swift.Double, Swift.Float)"
            ) == (Int, String, Bool, Double, Float).self
        )
        #expect(
            resolveRuntimeType(
                "(Swift.Int, Swift.String, Swift.Bool, Swift.Double, Swift.Float, Swift.Character)"
            ) == (Int, String, Bool, Double, Float, Character).self
        )
    }

    @Test func labeledTuplesResolveAtEveryArity() {
        #expect(
            resolveRuntimeType("(a: Swift.Int, b: Swift.String)")
                == (a: Int, b: String).self
        )
        #expect(
            resolveRuntimeType(
                "(a: Swift.Int, b: Swift.String, c: Swift.Bool, d: Swift.Double)"
            ) == (a: Int, b: String, c: Bool, d: Double).self
        )
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

    @Test func linkedGenericClassAccessorsReconstructExactClassMetadata() throws {
        let intBox = try #require(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAssociatedBox",
                arguments: [Int.self]
            )
        )
        let stringBox = try #require(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAssociatedBox",
                arguments: [String.self]
            )
        )
        let pair = try #require(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAssociatedPair",
                arguments: [Optional<[Int]>.self, String.self]
            )
        )
        let alternative = try #require(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAlternativeAssociatedBox",
                arguments: [Int.self]
            )
        )

        #expect(
            ObjectIdentifier(intBox.type)
                == ObjectIdentifier(ExternalAssociatedBox<Int>.self)
        )
        #expect(
            ObjectIdentifier(stringBox.type)
                == ObjectIdentifier(ExternalAssociatedBox<String>.self)
        )
        #expect(
            ObjectIdentifier(pair.type)
                == ObjectIdentifier(
                    ExternalAssociatedPair<[Int]?, String>.self
                )
        )
        #expect(intBox.constructor == stringBox.constructor)
        #expect(intBox.constructor != alternative.constructor)
        #expect(
            intBox.constructor.name
                == "TestDoublesFixtures.ExternalAssociatedBox"
        )
    }

    @Test func genericClassAccessorRejectsNonClassesAndConstrainedClasses() {
        #expect(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAssociatedValue",
                arguments: [Int.self]
            ) == nil
        )
        #expect(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAssociatedChoice",
                arguments: [Int.self]
            ) == nil
        )
        #expect(
            genericClassType(
                named: "TestDoublesFixtures.ExternalConstrainedAssociatedBox",
                arguments: [Int.self]
            ) == nil
        )
    }

}
