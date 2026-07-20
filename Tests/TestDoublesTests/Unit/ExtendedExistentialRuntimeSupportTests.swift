import Testing

@testable import TestDoubles

/// The Swift runtime pre-builds fixed value witness tables for opaque
/// existentials with up to one witness table and class existentials with up
/// to two. Every larger extended existential is copied through
/// runtime-instantiated witnesses, which miscount witness tables on OS
/// runtimes older than the 26.4 releases (swiftlang/swift#85346).
struct ExtendedExistentialRuntimeSupportTests {
    @Test func singleRootOpaqueShapesUsePrebuiltValueWitnesses() {
        #expect(
            extendedExistentialUsesRuntimeInstantiatedValueWitnesses(
                isClassConstrained: false,
                numberOfWitnessTables: 1
            ) == false
        )
    }

    @Test func multiRootOpaqueShapesUseRuntimeInstantiatedValueWitnesses() {
        #expect(
            extendedExistentialUsesRuntimeInstantiatedValueWitnesses(
                isClassConstrained: false,
                numberOfWitnessTables: 2
            )
        )
    }

    @Test func classConstrainedShapesUsePrebuiltValueWitnessesUpToTwoRoots() {
        #expect(
            extendedExistentialUsesRuntimeInstantiatedValueWitnesses(
                isClassConstrained: true,
                numberOfWitnessTables: 2
            ) == false
        )
    }

    @Test func classConstrainedShapesBeyondTwoRootsUseRuntimeInstantiatedValueWitnesses() {
        #expect(
            extendedExistentialUsesRuntimeInstantiatedValueWitnesses(
                isClassConstrained: true,
                numberOfWitnessTables: 3
            )
        )
    }
}
