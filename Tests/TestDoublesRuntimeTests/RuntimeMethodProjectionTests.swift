import Testing
@testable import TestDoublesRuntimeMetadata

@Suite struct RuntimeMethodProjectionTests {
    @Test func semanticProjectionErasesRawDependentShapeDetails() {
        let argumentDependency = WitnessValueDependency.dictionary(
            key: .associatedType(name: "Key"),
            value: .genericClass(
                constructor: GenericClassID(
                    name: "Module.Box",
                    descriptorAddress: 1
                ),
                arguments: [
                    .optional(.associatedType(name: "Value")),
                    .associatedType(name: "Key")
                ]
            )
        )
        let resultDependency = WitnessValueDependency.result(
            success: .array(.associatedType(name: "Value")),
            failure: .optional(.associatedType(name: "Failure"))
        )
        let typedErrorDependency = WitnessValueDependency.genericClass(
            constructor: GenericClassID(
                name: "Module.ErrorBox",
                descriptorAddress: 2
            ),
            arguments: [
                .associatedType(name: "Failure"),
                .associatedType(name: "Value")
            ]
        )
        let method = MethodDescriptor(
            kind: .method,
            name: "transform",
            index: 0,
            argumentTypes: [[String: Int].self],
            returnType: Result<[Int], ProjectionError>.self,
            argumentDependencies: [argumentDependency],
            returnDependency: resultDependency,
            typedErrorType: ProjectionError.self,
            typedErrorDependency: typedErrorDependency,
            isThrowing: true
        )

        let runtimeMethod = method.runtimeMethod

        #expect(method.arguments[0].value.dependency == argumentDependency)
        #expect(method.result.dependency == resultDependency)
        #expect(
            method.effects.throwing.typedError?.dependency == typedErrorDependency
        )
        #expect(
            runtimeMethod.argumentAssociatedTypeUses.map(\.names)
                == [["Key", "Value"]]
        )
        #expect(runtimeMethod.returnAssociatedTypeUse.names == ["Value", "Failure"])
        #expect(
            runtimeMethod.typedErrorAssociatedTypeUse?.names
                == ["Failure", "Value"]
        )
        #expect(runtimeMethod.signatureDescription.contains("Module.Box") == false)
        #expect(runtimeMethod.signatureDescription.contains("Module.ErrorBox") == false)
    }

    private enum ProjectionError: Error {}
}
