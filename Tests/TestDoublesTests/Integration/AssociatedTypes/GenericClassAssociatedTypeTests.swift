import TestDoublesFixtures
import Testing
@testable import TestDoubles

@inline(never)
private func useLinkedGenericClassAssociatedProbe(
    _ value: any ExternalGenericClassAssociatedProbe<Int>
) -> Int {
    value.transform(box: ExternalAssociatedBox(1)).value
}

@inline(never)
private func useLinkedGenericStructAssociatedProbe(
    _ value: any ExternalGenericStructAssociatedProbe<Int>
) -> Int {
    value.transform(ExternalAssociatedValue(1)).value
}

@inline(never)
private func useLinkedGenericEnumAssociatedProbe(
    _ value: any ExternalGenericEnumAssociatedProbe<Int>
) -> Int {
    switch value.transform(.value(1)) {
        case .value(let result): result
    }
}

@inline(never)
private func useLinkedConstrainedGenericClassAssociatedProbe(
    _ value: any ExternalConstrainedGenericClassAssociatedProbe<Int>
) -> Int {
    value.transform(ExternalConstrainedAssociatedBox(1)).value
}

@Suite struct GenericClassAssociatedTypeTests {
    @Test func automaticDiscoverySupportsLinkedGenericClasses() throws {
        #expect(
            useLinkedGenericClassAssociatedProbe(
                RealExternalGenericClassAssociatedProbe()
            ) == 1
        )
        typealias ProbeStub = Stub<
            any ExternalGenericClassAssociatedProbe<Int>
        >
        let stub = try ProbeStub()

        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedBox<Int>.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedBox",
                [.associatedType("Element")]
            )
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedPair<[Int]?, String>.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedPair",
                [
                    .optional(.array(.associatedType("Element"))),
                    .independent
                ]
            )
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 2)),
            type: Optional<ExternalAssociatedBox<Int>>.self,
            dependency: .optional(
                .genericClass(
                    "TestDoublesFixtures.ExternalAssociatedBox",
                    [.associatedType("Element")]
                )
            )
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 3)),
            type: [ExternalAssociatedBox<Int>].self,
            dependency: .array(
                .genericClass(
                    "TestDoublesFixtures.ExternalAssociatedBox",
                    [.associatedType("Element")]
                )
            )
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 4)),
            type: ExternalAssociatedPair<
                ExternalAssociatedBox<Int>,
                String
            >.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedPair",
                [
                    .genericClass(
                        "TestDoublesFixtures.ExternalAssociatedBox",
                        [.associatedType("Element")]
                    ),
                    .independent
                ]
            )
        )

        let placeholder = ExternalAssociatedBox(0)
        stub.when(returning: placeholder) {
            $0.transform(box: any(using: placeholder))
        }.then { (box: ExternalAssociatedBox<Int>) in
            ExternalAssociatedBox(box.value + 1)
        }
        let probe: any ExternalGenericClassAssociatedProbe<Int> = stub()
        #expect(probe.transform(box: ExternalAssociatedBox(41)).value == 42)
    }

    @Test func explicitConcreteSchemasDoNotEraseGenericClassDependency() {
        _ = RealExternalGenericClassAssociatedProbe()
        typealias ProbeStub = Stub<
            any ExternalGenericClassAssociatedProbe<Int>
        >
        let value = ProbeStub.Requirement.Value.self

        expectStubError {
            _ = try ProbeStub(
                .method(
                    value.concrete(ExternalAssociatedBox<Int>.self),
                    returning: value.concrete(ExternalAssociatedBox<Int>.self)
                ),
                .method(
                    value.concrete(
                        ExternalAssociatedPair<[Int]?, String>.self
                    ),
                    returning: value.concrete(
                        ExternalAssociatedPair<[Int]?, String>.self
                    )
                ),
                .method(
                    value.concrete(Optional<ExternalAssociatedBox<Int>>.self),
                    returning: value.concrete(
                        Optional<ExternalAssociatedBox<Int>>.self
                    )
                ),
                .method(
                    value.concrete([ExternalAssociatedBox<Int>].self),
                    returning: value.concrete(
                        [ExternalAssociatedBox<Int>].self
                    )
                ),
                .method(
                    value.concrete(
                        ExternalAssociatedPair<
                            ExternalAssociatedBox<Int>,
                            String
                        >.self
                    ),
                    returning: value.concrete(
                        ExternalAssociatedPair<
                            ExternalAssociatedBox<Int>,
                            String
                        >.self
                    )
                )
            )
        } matching: { error in
            guard case .requirementMismatch(_, let index, _, _) = error else {
                return false
            }
            return index == 0
        }
    }

    @Test func automaticDiscoveryRejectsGenericStructsEnumsAndConstraints() {
        #expect(
            useLinkedGenericStructAssociatedProbe(
                RealExternalGenericStructAssociatedProbe()
            ) == 1
        )
        #expect(
            useLinkedGenericEnumAssociatedProbe(
                RealExternalGenericEnumAssociatedProbe()
            ) == 1
        )
        #expect(
            useLinkedConstrainedGenericClassAssociatedProbe(
                RealExternalConstrainedGenericClassAssociatedProbe()
            ) == 1
        )

        for operation in [
            {
                _ = try Stub<any ExternalGenericStructAssociatedProbe<Int>>()
            },
            {
                _ = try Stub<any ExternalGenericEnumAssociatedProbe<Int>>()
            },
            {
                _ = try Stub<
                    any ExternalConstrainedGenericClassAssociatedProbe<Int>
                >()
            }
        ] {
            expectUnsupportedProtocolShape(
                containing: "Generic structs, enums, constrained classes"
            ) {
                try operation()
            }
        }
    }
}

private indirect enum GenericClassDependencyShape: Equatable {
    case independent
    case associatedType(String)
    case optional(Self)
    case array(Self)
    case set(Self)
    case dictionary(key: Self, value: Self)
    case result(success: Self, failure: Self)
    case genericClass(String, [Self])
}

private func genericClassDependencyShape(
    _ dependency: WitnessValueDependency
) -> GenericClassDependencyShape {
    switch dependency {
        case .independent:
            .independent
        case .associatedType(let reference):
            .associatedType(reference.name)
        case .optional(let wrapped):
            .optional(genericClassDependencyShape(wrapped))
        case .array(let element):
            .array(genericClassDependencyShape(element))
        case .set(let element):
            .set(genericClassDependencyShape(element))
        case .dictionary(let key, let value):
            .dictionary(
                key: genericClassDependencyShape(key),
                value: genericClassDependencyShape(value)
            )
        case .result(let success, let failure):
            .result(
                success: genericClassDependencyShape(success),
                failure: genericClassDependencyShape(failure)
            )
        case .genericClass(let constructor, let arguments):
            .genericClass(
                constructor.name,
                arguments.map(genericClassDependencyShape)
            )
    }
}

private func assertGenericClassDescriptor<Value>(
    _ method: MethodDescriptor,
    type: Value.Type,
    dependency: GenericClassDependencyShape,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let argument = try #require(
        method.arguments.first,
        sourceLocation: sourceLocation
    )
    #expect(method.arguments.count == 1, sourceLocation: sourceLocation)
    #expect(
        ObjectIdentifier(argument.value.type) == ObjectIdentifier(type),
        sourceLocation: sourceLocation
    )
    #expect(
        ObjectIdentifier(method.result.type) == ObjectIdentifier(type),
        sourceLocation: sourceLocation
    )
    #expect(
        genericClassDependencyShape(argument.value.dependency) == dependency,
        sourceLocation: sourceLocation
    )
    #expect(
        genericClassDependencyShape(method.result.dependency) == dependency,
        sourceLocation: sourceLocation
    )
    #expect(argument.value.convention == .concrete, sourceLocation: sourceLocation)
    #expect(method.result.convention == .concrete, sourceLocation: sourceLocation)
    #expect(
        isSingleReference(argument.value.layout),
        sourceLocation: sourceLocation
    )
    #expect(isSingleReference(method.result.layout), sourceLocation: sourceLocation)
}

private func isSingleReference(_ layout: ABIClass) -> Bool {
    if case .integer(words: 1) = layout { true } else { false }
}
