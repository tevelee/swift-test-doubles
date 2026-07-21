import Testing
@testable import TestDoubles

private protocol FirstDependencyScope {
    associatedtype Value
}

private protocol SecondDependencyScope {
    associatedtype Value
}

@Suite struct WitnessValueDependencyTests {
    @Test func dependencyRetainsStructureAndDeclaringProtocolIdentity() throws {
        let firstProtocol = try #require(
            inspectStubProtocolMetadata(
                (any FirstDependencyScope).self,
                typeDescription: "FirstDependencyScope"
            ).protocols.first
        )
        let secondProtocol = try #require(
            inspectStubProtocolMetadata(
                (any SecondDependencyScope).self,
                typeDescription: "SecondDependencyScope"
            ).protocols.first
        )
        let first = WitnessValueDependency.associatedType(
            id: AssociatedTypeID(
                protocolDescriptor: firstProtocol,
                name: "Value"
            )
        )
        let second = WitnessValueDependency.associatedType(
            id: AssociatedTypeID(
                protocolDescriptor: secondProtocol,
                name: "Value"
            )
        )

        #expect(first != second)
        #expect(
            WitnessValueDependency.optional(first)
                != WitnessValueDependency.array(first)
        )
        #expect(
            WitnessValueDependency.dictionary(
                key: first,
                value: .independent
            )
                != .dictionary(
                    key: .independent,
                    value: first
                )
        )
        #expect(first.legacyProjection == .associatedType(name: "Value"))
        #expect(first.usesOpaqueValueWitnessConvention)
        #expect(
            WitnessValueDependency.optional(first)
                .usesOpaqueValueWitnessConvention
        )
        #expect(
            WitnessValueDependency.optional(.array(first))
                .usesOpaqueValueWitnessConvention == false
        )
        #expect(
            WitnessValueDependency.array(.optional(first))
                .usesOpaqueValueWitnessConvention == false
        )
        #expect(
            WitnessValueDependency.dictionary(key: first, value: second)
                .usesOpaqueValueWitnessConvention == false
        )
        #expect(
            WitnessValueDependency.result(
                success: first,
                failure: .independent
            ).usesOpaqueValueWitnessConvention
        )
        #expect(
            WitnessValueDependency.result(
                success: .array(first),
                failure: .independent
            ).usesOpaqueValueWitnessConvention == false
        )
        #expect(
            WitnessValueDependency.result(
                success: .independent,
                failure: second
            ).usesOpaqueValueWitnessConvention
        )
        let genericClass = WitnessValueDependency.genericClass(
            constructor: GenericClassID(
                name: "Module.Box",
                descriptorAddress: 1
            ),
            arguments: [first]
        )
        #expect(genericClass.isAssociatedTypeDependent)
        #expect(genericClass.usesOpaqueValueWitnessConvention == false)
        #expect(
            genericClass
                != .genericClass(
                    constructor: GenericClassID(
                        name: "Module.Box",
                        descriptorAddress: 2
                    ),
                    arguments: [first]
                )
        )
    }
}
