import TestDoublesRuntime

import Testing

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
