import Testing
@testable import TestDoublesRuntimeMetadata

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
        let reference = WitnessValueDependency.referenceAssociatedType(
            id: AssociatedTypeID(
                protocolDescriptor: firstProtocol,
                name: "Value"
            )
        )
        let secondReference = WitnessValueDependency.referenceAssociatedType(
            id: AssociatedTypeID(
                protocolDescriptor: secondProtocol,
                name: "Value"
            )
        )

        #expect(first != second)
        #expect(first != reference)
        #expect(reference != secondReference)
        #expect(reference.legacyProjection == .associatedType(name: "Value"))
        #expect(reference.associatedTypeUse.names == ["Value"])
        #expect(reference.associatedTypeUse == first.associatedTypeUse)
        #expect(reference.usesOpaqueValueWitnessConvention == false)
        #expect(reference.usesSupportedReferenceAssociatedTransport)
        #expect(
            WitnessValueDependency.optional(reference)
                .usesSupportedReferenceAssociatedTransport
        )
        #expect(
            WitnessValueDependency.optional(.optional(reference))
                .usesSupportedReferenceAssociatedTransport == false
        )
        #expect(
            WitnessValueDependency.array(reference)
                .usesSupportedReferenceAssociatedTransport == false
        )
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
        #expect(genericClass.associatedTypeUse.names == ["Value"])
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

    @Test func semanticUseErasesRawDependencyShapeInSourceOrder() {
        let key = WitnessValueDependency.associatedType(name: "Key")
        let value = WitnessValueDependency.associatedType(name: "Value")
        let failure = WitnessValueDependency.associatedType(name: "Failure")
        let shape = WitnessValueDependency.result(
            success: .dictionary(
                key: key,
                value: .optional(.array(value))
            ),
            failure: .genericClass(
                constructor: GenericClassID(
                    name: "Module.ErrorBox",
                    descriptorAddress: 1
                ),
                arguments: [value, failure, key]
            )
        )

        #expect(shape.associatedTypeUse.names == ["Key", "Value", "Failure"])
        #expect(
            WitnessValueDependency.optional(value).associatedTypeUse
                == WitnessValueDependency.array(value).associatedTypeUse
        )
        #expect(
            WitnessValueDependency.genericClass(
                constructor: GenericClassID(
                    name: "Module.OtherBox",
                    descriptorAddress: 2
                ),
                arguments: [value]
            ).associatedTypeUse
                == value.associatedTypeUse
        )
    }
}
import TestDoublesRuntime
