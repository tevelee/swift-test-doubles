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
private func useLinkedGenericParentAssociatedProbe(
    _ value: any ExternalGenericParentAssociatedProbe<Int>
) -> Int {
    value.transform(ExternalGenericParent.Payload(outer: 1)).outer
}

@inline(never)
private func useLinkedConstrainedGenericParentAssociatedProbe(
    _ value: any ExternalConstrainedGenericParentAssociatedProbe<String>
) -> String {
    value.transform(ConstrainedGenericParent.Payload(outer: "one")).outer
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
private func useLinkedConstrainedGenericStructAssociatedProbe(
    _ value: any ExternalConstrainedGenericStructAssociatedProbe<Int>
) -> Int {
    value.transform(ExternalSecondParameterConstrainedPair(1, "one")).first
}

@inline(never)
private func useLinkedConstrainedGenericClassAssociatedProbe(
    _ value: any ExternalConstrainedGenericClassAssociatedProbe<Int>
) -> Int {
    value.transform(ExternalConstrainedAssociatedBox(1)).value
}

@Suite struct GenericNominalAssociatedTypeTests {
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
            $0.transform(box: Match.any(using: placeholder))
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

    @Test func automaticDiscoverySupportsGenericStructsAndEnums() throws {
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

        let structStub = try Stub<any ExternalGenericStructAssociatedProbe<Int>>()
        try assertGenericValueDescriptor(
            #require(structStub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedValue<Int>.self,
            associatedTypeNames: ["Element"]
        )
        let structPlaceholder = ExternalAssociatedValue(0)
        structStub.when(returning: structPlaceholder) {
            $0.transform(Match.any(using: structPlaceholder))
        }.then { (value: ExternalAssociatedValue<Int>) in
            ExternalAssociatedValue(value.value + 1)
        }
        #expect(
            structStub().transform(ExternalAssociatedValue(41)).value == 42
        )

        let enumStub = try Stub<any ExternalGenericEnumAssociatedProbe<Int>>()
        try assertGenericValueDescriptor(
            #require(enumStub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedChoice<Int>.self,
            associatedTypeNames: ["Element"]
        )
        let enumPlaceholder = ExternalAssociatedChoice<Int>.value(0)
        enumStub.when(returning: enumPlaceholder) {
            $0.transform(Match.any(using: enumPlaceholder))
        }.then { (value: ExternalAssociatedChoice<Int>) in
            switch value {
                case .value(let element): .value(element + 1)
            }
        }
        let enumResult = enumStub().transform(.value(41))
        switch enumResult {
            case .value(let element): #expect(element == 42)
        }

        #expect(
            useLinkedConstrainedGenericStructAssociatedProbe(
                RealExternalConstrainedGenericStructAssociatedProbe()
            ) == 1
        )
        let constrainedStructStub = try Stub<
            any ExternalConstrainedGenericStructAssociatedProbe<Int>
        >()
        try assertGenericValueDescriptor(
            #require(constrainedStructStub.recorder.runtimeMethod(for: 0)),
            type: ExternalSecondParameterConstrainedPair<Int, String>.self,
            associatedTypeNames: ["Element"]
        )
        let constrainedPlaceholder = ExternalSecondParameterConstrainedPair(
            0,
            "zero"
        )
        constrainedStructStub.when(returning: constrainedPlaceholder) {
            $0.transform(Match.any(using: constrainedPlaceholder))
        }.then { (value: ExternalSecondParameterConstrainedPair<Int, String>) in
            ExternalSecondParameterConstrainedPair(value.first + 1, value.second)
        }
        #expect(
            constrainedStructStub().transform(
                ExternalSecondParameterConstrainedPair(41, "answer")
            ).first == 42
        )
    }

    @Test func automaticDiscoverySupportsGenericNominalsNestedInGenericParents() throws {
        #expect(
            useLinkedGenericParentAssociatedProbe(
                RealExternalGenericParentAssociatedProbe()
            ) == 1
        )

        let stub = try Stub<any ExternalGenericParentAssociatedProbe<Int>>()
        try assertGenericValueDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: ExternalGenericParent<Int>.Payload.self,
            associatedTypeNames: ["Element"]
        )

        let placeholder = ExternalGenericParent<Int>.Payload(outer: 0)
        stub.when(returning: placeholder) {
            $0.transform(Match.any(using: placeholder))
        }.then { (value: ExternalGenericParent<Int>.Payload) in
            ExternalGenericParent.Payload(outer: value.outer + 1)
        }
        #expect(
            stub().transform(ExternalGenericParent.Payload(outer: 41)).outer == 42
        )
    }

    @Test func automaticDiscoverySupportsConstrainedGenericParents() throws {
        #expect(
            useLinkedConstrainedGenericParentAssociatedProbe(
                RealExternalConstrainedGenericParentAssociatedProbe()
            ) == "one"
        )

        let stub = try Stub<
            any ExternalConstrainedGenericParentAssociatedProbe<String>
        >()
        try assertGenericValueDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: ConstrainedGenericParent<String>.Payload.self,
            associatedTypeNames: ["Element"]
        )

        let placeholder = ConstrainedGenericParent<String>.Payload(outer: "zero")
        stub.when(returning: placeholder) {
            $0.transform(Match.any(using: placeholder))
        }.then { (value: ConstrainedGenericParent<String>.Payload) in
            ConstrainedGenericParent.Payload(outer: value.outer + "!")
        }
        #expect(
            stub().transform(ConstrainedGenericParent.Payload(outer: "answer")).outer
                == "answer!"
        )
    }

    @Test func automaticDiscoverySupportsConstrainedGenericClasses() throws {
        // A constrained generic class must resolve the conformance-witness key
        // argument alongside its type metadata. This uses the same resolver
        // path as other constrained generic nominal metadata.
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
            $0.transform(Match.any(using: placeholder))
        }.then { (box: ExternalConstrainedAssociatedBox<Int>) in
            ExternalConstrainedAssociatedBox(box.value + 1)
        }
        let probe: any ExternalConstrainedGenericClassAssociatedProbe<Int> = stub()
        #expect(
            probe.transform(ExternalConstrainedAssociatedBox(41)).value == 42
        )
    }

    @Test func automaticDiscoverySupportsWiderGenericNominalArity() throws {
        _ = RealExternalWideGenericNominalAssociatedProbe()
        typealias Probe = any ExternalWideGenericNominalAssociatedProbe<Int>
        let stub = try Stub<Probe>()
        let classPlaceholder = ExternalAssociatedTriple(0, "zero", 0)
        let valuePlaceholder = ExternalAssociatedTripleValue(0, "zero", 0)

        try assertGenericClassDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedTriple<Int, String, Int>.self,
            associatedTypeNames: ["Element"]
        )
        try assertGenericValueDescriptor(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedTripleValue<Int, String, Int>.self,
            associatedTypeNames: ["Element"]
        )

        stub.when(returning: classPlaceholder) {
            $0.transform(Match.any(using: classPlaceholder))
        }.then { (value: ExternalAssociatedTriple<Int, String, Int>) in
            ExternalAssociatedTriple(
                value.first + 1,
                value.second,
                value.third
            )
        }
        stub.when(returning: valuePlaceholder) {
            $0.transform(Match.any(using: valuePlaceholder))
        }.then {
            (value: ExternalAssociatedTripleValue<Int, String, Int>) in
            ExternalAssociatedTripleValue(
                value.first + 1,
                value.second,
                value.third
            )
        }

        let probe: Probe = stub()
        #expect(
            probe.transform(
                ExternalAssociatedTriple(41, "answer", 42)
            ).first == 42
        )
        #expect(
            probe.transform(
                ExternalAssociatedTripleValue(41, "answer", 42)
            ).first == 42
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

private func assertGenericValueDescriptor<Value>(
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
    #expect(
        argument.value.convention == .associatedType(name: "Element"),
        sourceLocation: sourceLocation
    )
    #expect(
        method.result.convention == .associatedType(name: "Element"),
        sourceLocation: sourceLocation
    )
}
