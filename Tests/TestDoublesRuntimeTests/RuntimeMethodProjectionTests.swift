import Testing
@testable import TestDoublesRuntime

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

    @Test func inoutSelfAlwaysUsesCallerOwnedIndirectStorage() {
        let method = MethodDescriptor(
            kind: .method,
            name: "update",
            index: 0,
            argumentTypes: [FabricatedPayload.self],
            returnType: Void.self,
            argumentConventions: [.inoutSelf],
            selfIsClassConstrained: true
        )

        if case .indirect = method.argumentLayouts[0] {
            // Expected: inout always passes the caller's storage address.
        } else {
            Issue.record("Expected indirect inout Self transport")
        }
        #expect(method.runtimeMethod.argumentConventions == [.inoutSelf])
        #expect(
            method.runtimeMethod.signatureDescription
                == method.signatureDescription
        )
    }

    @Test func nestedOptionalSelfUsesIndirectStorageAndSemanticProjection() {
        let method = MethodDescriptor(
            kind: .method,
            name: "accept",
            index: 0,
            argumentTypes: [Optional<FabricatedPayload?>.self],
            returnType: Void.self,
            argumentConventions: [.nestedOptionalSelf],
            selfIsClassConstrained: true
        )

        if case .indirect = method.argumentLayouts[0] {
            // Expected: nested optional payloads use their value witness ABI.
        } else {
            Issue.record("Expected indirect nested Optional Self transport")
        }
        #expect(
            method.runtimeMethod.argumentConventions
                == [.nestedOptionalSelf]
        )
        #expect(
            method.runtimeMethod.signatureDescription
                == method.signatureDescription
        )
    }

    @Test func arraySelfUsesOneFixedLayoutValueWord() {
        let method = MethodDescriptor(
            kind: .method,
            name: "accept",
            index: 0,
            argumentTypes: [[FabricatedPayload].self],
            returnType: Void.self,
            argumentConventions: [.arraySelf]
        )

        if case .integer(words: 1) = method.argumentLayouts[0] {
            // Expected: Array has a fixed one-word value representation.
        } else {
            Issue.record("Expected one-word Array<Self> transport")
        }
        #expect(method.runtimeMethod.argumentConventions == [.arraySelf])
        #expect(
            method.runtimeMethod.signatureDescription
                == method.signatureDescription
        )
    }

    @Test func optionalArraySelfUsesOneFixedLayoutValueWord() {
        let method = MethodDescriptor(
            kind: .method,
            name: "accept",
            index: 0,
            argumentTypes: [Optional<[FabricatedPayload]>.self],
            returnType: Void.self,
            argumentConventions: [.optionalArraySelf]
        )

        if case .integer(words: 1) = method.argumentLayouts[0] {
            // Expected: Optional<Array<Self>> uses Array's null spare value.
        } else {
            Issue.record("Expected one-word Optional<Array<Self>> transport")
        }
        #expect(
            method.runtimeMethod.argumentConventions
                == [.optionalArraySelf]
        )
        #expect(
            method.runtimeMethod.signatureDescription
                == method.signatureDescription
        )
    }

    private enum ProjectionError: Error {}
}
