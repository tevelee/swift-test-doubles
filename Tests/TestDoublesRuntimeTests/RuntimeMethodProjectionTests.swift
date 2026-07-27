import Testing
@testable import TestDoublesRuntimeMetadata

@Suite struct RuntimeMethodProjectionTests {
    @Test func semanticProjectionErasesRawDependentShapeDetails() {
        let argumentDependency = WitnessValueDependency.dictionary(
            key: .associatedType(name: "Key"),
            value: .genericValue(
                constructor: GenericValueID(
                    name: "Module.ValueBox",
                    descriptorAddress: 1,
                    kind: .struct
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
        #expect(
            runtimeMethod.signatureDescription.contains("Module.ValueBox")
                == false
        )
        #expect(runtimeMethod.signatureDescription.contains("Module.ErrorBox") == false)
    }

    @Test func semanticProjectionPreservesRequirementSignatures() {
        let descriptors: [MethodDescriptor] = [
            MethodDescriptor(
                kind: .method,
                name: "transform",
                index: 0,
                argumentTypes: [Int.self],
                returnType: String.self,
                isThrowing: true,
                isAsync: true
            ),
            MethodDescriptor(
                kind: .initializer,
                name: "init(value:)",
                index: 1,
                argumentTypes: [String.self],
                returnType: Any.self,
                returnConvention: .selfType,
                isThrowing: true,
                hasReliableThrowing: false
            ),
            MethodDescriptor(
                kind: .getter,
                name: "value",
                index: 2,
                argumentTypes: [Int.self],
                returnType: String.self,
                returnConvention: .associatedType(name: "Element")
            ),
            MethodDescriptor(
                kind: .setter,
                name: "value(_:)",
                index: 3,
                argumentTypes: [String.self, Int.self],
                returnType: Void.self
            ),
            MethodDescriptor(
                kind: .method,
                name: "typedFailure",
                index: 4,
                argumentTypes: [Int.self],
                returnType: String.self,
                typedErrorType: ProjectionError.self,
                typedErrorDependency: .associatedType(name: "Failure"),
                isThrowing: true
            )
        ]

        for descriptor in descriptors {
            #expect(
                descriptor.runtimeMethod.signatureDescription
                    == descriptor.signatureDescription
            )
        }
    }

    private enum ProjectionError: Error {}
}
