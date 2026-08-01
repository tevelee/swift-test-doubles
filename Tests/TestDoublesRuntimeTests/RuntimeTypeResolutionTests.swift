import Foundation
import Testing
@testable import TestDoublesRuntimeMetadata
import TestDoublesFixtures
import TestDoublesResilientFixtures

private struct NominalResilientTupleWrapper {
    let pair: (ResilientValueArgument, UInt64)
}

private indirect enum RecursiveValueBox<Value> {
    case value(Value)
    case child(RecursiveValueBox)
}

/// Unit coverage for demangled-name resolution: no stubs are constructed and
/// no witness tables are involved.
@Suite struct RuntimeTypeResolutionTests {
    @Test func qualifiedProtocolNamesResolveToOrdinaryExistentialMetadata() {
        #expect(resolveRuntimeType("Swift.Encodable") == (any Encodable).self)
        #expect(
            resolveRuntimeType("TestDoublesFixtures.ExternalFirstGenericConstraint")
                == (any ExternalFirstGenericConstraint).self
        )
        #expect(
            resolveRuntimeType("TestDoublesFixtures.ExternalReferenceAssociatedMarker")
                == (any ExternalReferenceAssociatedMarker).self
        )
        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalNestedProtocolNamespace.Constraint"
            ) == (any ExternalNestedProtocolNamespace.Constraint).self
        )
    }

    @Test func qualifiedProtocolCompositionsResolveToOrdinaryExistentialMetadata() {
        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalFirstGenericConstraint & "
                    + "TestDoublesFixtures.ExternalSecondGenericConstraint"
            ) == (any ExternalFirstGenericConstraint & ExternalSecondGenericConstraint).self
        )
        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalFirstGenericConstraint & Swift.Sendable"
            ) == (any ExternalFirstGenericConstraint & Sendable).self
        )
    }

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

    @Test func constructorSpellingsResolveComparableRanges() {
        #expect(
            resolveRuntimeType("Swift.ClosedRange<Swift.Int>")
                == ClosedRange<Int>.self
        )
        #expect(
            resolveRuntimeType("Swift.Range<Swift.String>")
                == Range<String>.self
        )
    }

    @Test func genericAccessorResolvesComparableRangesWithoutATypeSpecificOpener() {
        #expect(
            genericNominalType(named: "Swift.ClosedRange<Swift.Int>")
                == ClosedRange<Int>.self
        )
        #expect(
            genericNominalType(named: "Swift.Range<\(String(reflecting: Date.self))>")
                == Range<Date>.self
        )
    }

    @Test func genericAccessorResolvesNestedNominalTypes() {
        #expect(
            genericNominalType(
                named: "TestDoublesFixtures.ExternalNestedGenericNamespace.Box<Swift.Int>"
            ) == ExternalNestedGenericNamespace.Box<Int>.self
        )
    }

    @Test func rangeContainingAResilientBoundHasAnIndirectArgumentCandidate() {
        #expect(
            argumentABIClassCandidates(for: ClosedRange<ResilientValueArgument>.self)
                .contains(.indirect)
        )
        #expect(
            argumentABIClassCandidates(for: Optional<ResilientValueArgument>.self)
                .contains(.indirect)
        )
        #expect(
            argumentABIClassCandidates(
                for: Result<ResilientValueArgument, ResilientRuntimeError>.self
            ).contains(.indirect)
        )
        #expect(
            argumentABIClassCandidates(for: ClosedRange<Int>.self) == [
                abiClass(for: ClosedRange<Int>.self)
            ]
        )
    }

    @Test func recursiveGenericFieldsDoNotRevisitTheSameSpecialization() {
        #expect(
            argumentABIClassCandidates(for: RecursiveValueBox<Int>.self)
                == [abiClass(for: RecursiveValueBox<Int>.self)]
        )
        #expect(
            argumentABIClassCandidates(
                for: RecursiveValueBox<ResilientValueArgument>.self
            ).contains(.indirect)
        )
    }

    @Test func onlyTopLevelTuplesWithAResilientMemberRequireStructuralTransport() {
        #expect(
            requiresStructuralABITransport(
                for: (ResilientValueArgument, UInt64).self
            )
        )
        #expect(
            requiresStructuralABITransport(
                for: Optional<(ResilientValueArgument, UInt64)>.self
            ) == false
        )
        #expect(
            requiresStructuralABITransport(
                for: NominalResilientTupleWrapper.self
            ) == false
        )
        #expect(
            argumentABIClassCandidates(
                for: Optional<(ResilientValueArgument, UInt64)>.self
            ).contains(.indirect)
        )
        #expect(
            hasUncertainArgumentABITransport(
                for: Optional<(ResilientValueArgument, UInt64)>.self
            )
        )
        #expect(
            hasUncertainArgumentABITransport(
                for: (ResilientValueArgument, UInt64).self
            )
        )
        #expect(
            requiresStructuralABITransport(for: (FrozenValueArgument, UInt64).self)
                == false
        )
    }

    @Test func referenceBackedGenericContainersStayDirect() {
        #expect(
            argumentABIClassCandidates(for: Array<ResilientValueArgument>.self)
                == [abiClass(for: Array<ResilientValueArgument>.self)]
        )
        #expect(
            argumentABIClassCandidates(for: Array<URL>.self)
                == [abiClass(for: Array<URL>.self)]
        )
        #expect(
            argumentABIClassCandidates(for: Set<URL>.self)
                == [abiClass(for: Set<URL>.self)]
        )
        #expect(
            argumentABIClassCandidates(for: Dictionary<String, URL>.self)
                == [abiClass(for: Dictionary<String, URL>.self)]
        )
        #expect(
            argumentABIClassCandidates(for: Optional<[URL]>.self)
                == [abiClass(for: Optional<[URL]>.self)]
        )
        #expect(
            argumentABIClassCandidates(for: SIMD8<Float>.self)
                == [abiClass(for: SIMD8<Float>.self)]
        )
    }

    @Test func genericFieldResolutionDoesNotReuseAnotherSpecializationsLayout() {
        // Both specializations share `ClosedRange`'s field descriptor. Resolve
        // the floating-point-bound form first to prove the later integer-bound
        // form reads its own generic argument metadata rather than a cache
        // entry keyed only by that shared descriptor.
        _ = abiClass(for: ClosedRange<Date>.self)

        guard case .integer(let words) = abiClass(for: ClosedRange<Int>.self)
        else {
            Issue.record("ClosedRange<Int> must use two integer registers.")
            return
        }
        #expect(words == 2)
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

    #if os(Linux) && arch(x86_64)
        @Test func ambiguousTypedThrowingFunctionResolutionDefersToValidation() throws {
            let spelling =
                "@Sendable (@Sendable (Swift.Int) -> Swift.String, Swift.Int) throws(TestDoublesFixtures.ExternalDynamicClosureError) -> @Sendable (Swift.Int) -> Swift.String"
            let syntax = try #require(DemangledTypeSyntax(spelling))

            #expect(
                resolveRuntimeType(
                    syntax,
                    containedInMangledSymbol: "intentionally-unmatched"
                ) != nil
            )
        }
    #endif

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
        let triple = try #require(
            genericClassType(
                named: "TestDoublesFixtures.ExternalAssociatedTriple",
                arguments: [Int.self, String.self, Bool.self]
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
        #expect(
            ObjectIdentifier(triple.type)
                == ObjectIdentifier(
                    ExternalAssociatedTriple<Int, String, Bool>.self
                )
        )
        #expect(intBox.constructor == stringBox.constructor)
        #expect(intBox.constructor != alternative.constructor)
        #expect(
            intBox.constructor.name
                == "TestDoublesFixtures.ExternalAssociatedBox"
        )
    }

    @Test func genericClassAccessorRejectsNonClasses() {
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
    }

    @Test func genericClassAccessorResolvesConstrainedClasses() throws {
        // genericClassType used to decline any constrained class outright;
        // it now resolves through the same witness-table key-argument path
        // constrainedGenericNominalType uses for structs and enums.
        let resolved = try #require(
            genericClassType(
                named: "TestDoublesFixtures.ExternalConstrainedAssociatedBox",
                arguments: [Int.self]
            )
        )
        #expect(
            ObjectIdentifier(resolved.type)
                == ObjectIdentifier(ExternalConstrainedAssociatedBox<Int>.self)
        )
        #expect(
            resolved.constructor.name
                == "TestDoublesFixtures.ExternalConstrainedAssociatedBox"
        )
    }

    @Test func genericClassAccessorRejectsNonConformingConstrainedArgument() {
        #expect(
            genericClassType(
                named: "TestDoublesFixtures.ExternalConstrainedAssociatedBox",
                arguments: [NotHashableProbe.self]
            ) == nil
        )
    }

    @Test func constrainedGenericNominalsResolveThroughTheAccessorWitnessPath() {
        // ExternalConstrainedAssociatedBox<Value: Hashable> needs a second
        // key argument (Int's Hashable witness table) beyond its own type
        // metadata -- the case genericNominalType always declined before,
        // confirmed here against the real compiler-generated type as ground
        // truth via ObjectIdentifier, not just non-nil construction success.
        let resolved = resolveRuntimeType(
            "TestDoublesFixtures.ExternalConstrainedAssociatedBox<Swift.Int>"
        )
        #expect(resolved != nil)
        if let resolved {
            #expect(
                ObjectIdentifier(resolved)
                    == ObjectIdentifier(ExternalConstrainedAssociatedBox<Int>.self)
            )
        }
    }

    @Test func secondParameterConstraintResolvesTheRightWitnessTable() {
        // Only Second: Hashable is constrained here, exercising the "q_"
        // (depth 0, index 1) generic-parameter mangling rather than the "x"
        // (depth 0, index 0) shortcut a first-parameter constraint uses --
        // proving the witness table attaches to the correct key argument,
        // not just any of them.
        let resolved = resolveRuntimeType(
            "TestDoublesFixtures.ExternalSecondParameterConstrainedPair<Swift.String, Swift.Int>"
        )
        #expect(resolved != nil)
        if let resolved {
            #expect(
                ObjectIdentifier(resolved)
                    == ObjectIdentifier(
                        ExternalSecondParameterConstrainedPair<String, Int>.self
                    )
            )
        }
    }

    @Test func bothParametersConstrainedResolveTwoWitnessTables() {
        let resolved = resolveRuntimeType(
            "TestDoublesFixtures.ExternalBothParametersConstrainedPair<Swift.String, Swift.Int>"
        )
        #expect(resolved != nil)
        if let resolved {
            #expect(
                ObjectIdentifier(resolved)
                    == ObjectIdentifier(
                        ExternalBothParametersConstrainedPair<String, Int>.self
                    )
            )
        }
    }

    @Test func nonConformingArgumentFailsConstrainedGenericResolutionSafely() {
        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalConstrainedAssociatedBox<TestDoublesTests.NotHashableProbe>"
            ) == nil
        )
    }

    @Test func genericNominalsResolveMoreThanFourOrdinaryTypeArguments() {
        let resolved = resolveRuntimeType(
            "TestDoublesFixtures.ExternalSixParameterBox<Swift.Int, Swift.String, Swift.Bool, Swift.Double, Swift.Float, Swift.UInt>"
        )

        #expect(resolved != nil)
        if let resolved {
            #expect(
                ObjectIdentifier(resolved)
                    == ObjectIdentifier(
                        ExternalSixParameterBox<
                            Int,
                            String,
                            Bool,
                            Double,
                            Float,
                            UInt
                        >.self
                    )
            )
        }
    }

    @Test func oneParameterResolvesMultipleProtocolWitnesses() {
        let resolved = resolveRuntimeType(
            "TestDoublesFixtures.ExternalMultiplyConstrainedBox<Swift.Int>"
        )

        #expect(resolved != nil)
        if let resolved {
            #expect(
                ObjectIdentifier(resolved)
                    == ObjectIdentifier(
                        ExternalMultiplyConstrainedBox<Int>.self
                    )
            )
        }
    }

    @Test func severalParametersResolveAllProtocolWitnessesInDescriptorOrder() {
        let resolved = resolveRuntimeType(
            "TestDoublesFixtures.ExternalSeveralConstrainedArguments<Swift.String, Swift.Bool, Swift.Int>"
        )

        #expect(resolved != nil)
        if let resolved {
            #expect(
                ObjectIdentifier(resolved)
                    == ObjectIdentifier(
                        ExternalSeveralConstrainedArguments<
                            String,
                            Bool,
                            Int
                        >.self
                    )
            )
        }
    }

    @Test func missingOneOfSeveralProtocolConformancesFailsSafely() {
        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalMultiplyConstrainedBox<Swift.String>"
            ) == nil
        )
    }

    @Test
    @available(
        macOS 14.0,
        iOS 17.0,
        tvOS 17.0,
        watchOS 10.0,
        visionOS 1.0,
        macCatalyst 17.0,
        *
    )
    func metadataPackContextsRemainUnsupported() {
        _ = ExternalGenericPack<Int>.self

        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalGenericPack<Swift.Int>"
            ) == nil
        )
    }

    @Test
    @available(
        macOS 14.0,
        iOS 17.0,
        tvOS 17.0,
        watchOS 10.0,
        visionOS 1.0,
        macCatalyst 17.0,
        *
    )
    func witnessTablePackContextsRemainUnsupported() {
        _ = ExternalConstrainedGenericPack<Int>.self

        #expect(
            resolveRuntimeType(
                "TestDoublesFixtures.ExternalConstrainedGenericPack<Swift.Int>"
            ) == nil
        )
    }

}

/// Top-level (not function-local) so it has an ordinary resolvable qualified
/// name, letting `nonConformingArgumentFailsConstrainedGenericResolutionSafely`
/// exercise the "resolves the argument, then fails the conformance check"
/// path rather than failing earlier at "can't even resolve this name."
struct NotHashableProbe {}
import TestDoublesRuntime
