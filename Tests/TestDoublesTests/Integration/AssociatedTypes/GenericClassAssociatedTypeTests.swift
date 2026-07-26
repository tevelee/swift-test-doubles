import TestDoublesFixtures
import InternalRuntimeContract
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
            associatedTypeNames: ["Element"]
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedPair<[Int]?, String>.self,
            associatedTypeNames: ["Element"]
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 2)),
            type: Optional<ExternalAssociatedBox<Int>>.self,
            associatedTypeNames: ["Element"]
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 3)),
            type: [ExternalAssociatedBox<Int>].self,
            associatedTypeNames: ["Element"]
        )
        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 4)),
            type: ExternalAssociatedPair<
                ExternalAssociatedBox<Int>,
                String
            >.self,
            associatedTypeNames: ["Element"]
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

    @Test func automaticDiscoveryRejectsGenericStructsAndEnums() {
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

        for operation in [
            {
                _ = try Stub<any ExternalGenericStructAssociatedProbe<Int>>()
            },
            {
                _ = try Stub<any ExternalGenericEnumAssociatedProbe<Int>>()
            }
        ] {
            expectUnsupportedProtocolShape(
                containing: "Generic structs, enums, and other constructors"
            ) {
                try operation()
            }
        }
    }

    @Test func automaticDiscoverySupportsConstrainedGenericClasses() throws {
        // genericClassType used to decline any constrained class outright,
        // so a generic class embedding an associated type behind a
        // conformance requirement (Value: Hashable here) fell into the same
        // "Generic structs, enums, constrained classes" fail-closed bucket
        // as actual structs and enums. It now resolves the same witness-table
        // key-argument path constrainedGenericNominalType uses for a
        // standalone constrained type.
        #expect(
            useLinkedConstrainedGenericClassAssociatedProbe(
                RealExternalConstrainedGenericClassAssociatedProbe()
            ) == 1
        )
        typealias ProbeStub = Stub<
            any ExternalConstrainedGenericClassAssociatedProbe<Int>
        >
        let stub = try ProbeStub()

        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: ExternalConstrainedAssociatedBox<Int>.self,
            associatedTypeNames: ["Element"]
        )

        let placeholder = ExternalConstrainedAssociatedBox(0)
        stub.when(returning: placeholder) {
            $0.transform(any(using: placeholder))
        }.then { (box: ExternalConstrainedAssociatedBox<Int>) in
            ExternalConstrainedAssociatedBox(box.value + 1)
        }
        let probe: any ExternalConstrainedGenericClassAssociatedProbe<Int> = stub()
        #expect(
            probe.transform(ExternalConstrainedAssociatedBox(41)).value == 42
        )
    }
}

private func assertGenericClassDescriptor<Value>(
    _ method: RuntimeMethod,
    type: Value.Type,
    associatedTypeNames: [String],
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
        argument.value.associatedTypeUse.names == associatedTypeNames,
        sourceLocation: sourceLocation
    )
    #expect(
        method.result.associatedTypeUse.names == associatedTypeNames,
        sourceLocation: sourceLocation
    )
    #expect(argument.value.convention == .concrete, sourceLocation: sourceLocation)
    #expect(method.result.convention == .concrete, sourceLocation: sourceLocation)
}
