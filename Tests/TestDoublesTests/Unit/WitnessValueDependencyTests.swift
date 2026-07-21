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
    }
}
