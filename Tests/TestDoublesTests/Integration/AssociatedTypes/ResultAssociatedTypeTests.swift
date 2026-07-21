import Testing
@testable import TestDoubles

enum ResultAssociatedFailure: Error, Equatable {
    case failed
}

protocol ResultAssociatedTypeProbe<Element, Failure> {
    associatedtype Element: Hashable
    associatedtype Failure: Error

    func transform(
        opaque value: Result<Element, ResultAssociatedFailure>
    )
        -> Result<Element, ResultAssociatedFailure>
    func transform(
        opaqueFailure value: Result<[Int], Failure>
    )
        -> Result<[Int], Failure>
    func transform(
        fixed value: Result<[Element], ResultAssociatedFailure>
    )
        -> Result<[Element], ResultAssociatedFailure>
    func transform(
        set value: Result<Set<Element?>, ResultAssociatedFailure>
    )
        -> Result<Set<Element?>, ResultAssociatedFailure>
    func transform(
        nested value: [String: Result<[Element]?, ResultAssociatedFailure>]?
    ) -> [String: Result<[Element]?, ResultAssociatedFailure>]?
}

struct RealResultAssociatedTypeProbe:
    ResultAssociatedTypeProbe
{
    func transform(
        opaque value: Result<Int, ResultAssociatedFailure>
    ) -> Result<Int, ResultAssociatedFailure> {
        value
    }

    func transform(
        opaqueFailure value: Result<[Int], ResultAssociatedFailure>
    ) -> Result<[Int], ResultAssociatedFailure> {
        value
    }

    func transform(
        fixed value: Result<[Int], ResultAssociatedFailure>
    ) -> Result<[Int], ResultAssociatedFailure> {
        value
    }

    func transform(
        set value: Result<Set<Int?>, ResultAssociatedFailure>
    ) -> Result<Set<Int?>, ResultAssociatedFailure> {
        value
    }

    func transform(
        nested value: [String: Result<[Int]?, ResultAssociatedFailure>]?
    ) -> [String: Result<[Int]?, ResultAssociatedFailure>]? {
        value
    }
}

struct ResultAssociatedBox<Value> {}

protocol UnsupportedResultAssociatedTypeProbe<Element> {
    associatedtype Element

    func transform(
        _ value: Result<ResultAssociatedBox<Element>, ResultAssociatedFailure>
    ) -> Result<ResultAssociatedBox<Element>, ResultAssociatedFailure>
}

struct RealUnsupportedResultAssociatedTypeProbe:
    UnsupportedResultAssociatedTypeProbe
{
    func transform(
        _ value: Result<ResultAssociatedBox<Int>, ResultAssociatedFailure>
    ) -> Result<ResultAssociatedBox<Int>, ResultAssociatedFailure> {
        value
    }
}

private protocol ExplicitResultValidationProbe<Element> {
    associatedtype Element

    func transform(_ value: Result<Element, Never>) -> Result<Element, Never>
}

@inline(never)
private func useLinkedResultAssociatedTypeProbe(
    _ value: any ResultAssociatedTypeProbe<Int, ResultAssociatedFailure>
) -> Result<[Int], ResultAssociatedFailure> {
    value.transform(fixed: .success([1]))
}

@inline(never)
private func useLinkedUnsupportedResultAssociatedTypeProbe(
    _ value: any UnsupportedResultAssociatedTypeProbe<Int>
) -> Result<ResultAssociatedBox<Int>, ResultAssociatedFailure> {
    value.transform(.success(ResultAssociatedBox()))
}

@Suite struct ResultAssociatedTypeTests {
    @Test func automaticDiscoverySupportsResultAndRecursiveContainers() throws {
        #expect(
            useLinkedResultAssociatedTypeProbe(
                RealResultAssociatedTypeProbe()
            ) == .success([1])
        )
        typealias ProbeStub = Stub<
            any ResultAssociatedTypeProbe<Int, ResultAssociatedFailure>
        >
        let stub = try ProbeStub()

        try assertResultDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: Result<Int, ResultAssociatedFailure>.self,
            dependency: .result(
                success: .associatedType("Element"),
                failure: .independent
            ),
            convention: .associatedType(name: "Element"),
            isIndirect: true
        )
        try assertResultDescriptor(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: Result<[Int], ResultAssociatedFailure>.self,
            dependency: .result(
                success: .array(.independent),
                failure: .associatedType("Failure")
            ),
            convention: .associatedType(name: "Failure"),
            isIndirect: true
        )
        try assertResultDescriptor(
            #require(stub.recorder.runtimeMethod(for: 2)),
            type: Result<[Int], ResultAssociatedFailure>.self,
            dependency: .result(
                success: .array(.associatedType("Element")),
                failure: .independent
            ),
            convention: .concrete,
            isIndirect: false
        )
        try assertResultDescriptor(
            #require(stub.recorder.runtimeMethod(for: 3)),
            type: Result<Set<Int?>, ResultAssociatedFailure>.self,
            dependency: .result(
                success: .set(.optional(.associatedType("Element"))),
                failure: .independent
            ),
            convention: .concrete,
            isIndirect: false
        )
        try assertResultDescriptor(
            #require(stub.recorder.runtimeMethod(for: 4)),
            type: Optional<
                [String: Result<[Int]?, ResultAssociatedFailure>]
            >.self,
            dependency: .optional(
                .dictionary(
                    key: .independent,
                    value: .result(
                        success: .optional(.array(.associatedType("Element"))),
                        failure: .independent
                    )
                )
            ),
            convention: .concrete,
            isIndirect: false
        )

        stub.when(returning: Result<Int, ResultAssociatedFailure>.success(0)) {
            $0.transform(
                opaque: any(using: Result<Int, ResultAssociatedFailure>.success(0))
            )
        }.then {
            (value: Result<Int, ResultAssociatedFailure>) in
            value.map { $0 + 1 }
        }
        stub.when(returning: Result<[Int], ResultAssociatedFailure>.success([])) {
            $0.transform(
                fixed: any(
                    using: Result<[Int], ResultAssociatedFailure>.success([])
                )
            )
        }.then {
            (value: Result<[Int], ResultAssociatedFailure>) in
            value.map { $0.map { $0 + 1 } }
        }
        let probe:
            any ResultAssociatedTypeProbe<
                Int,
                ResultAssociatedFailure
            > = stub()
        #expect(probe.transform(opaque: .success(41)) == .success(42))
        #expect(probe.transform(fixed: .success([1, 2])) == .success([2, 3]))
    }

    @Test func explicitSchemasSupportResultAndRecursiveContainers() throws {
        _ = RealResultAssociatedTypeProbe()
        typealias ProbeStub = Stub<
            any ResultAssociatedTypeProbe<Int, ResultAssociatedFailure>
        >
        let value = ProbeStub.Requirement.Value.self
        let element = value.associatedType(named: "Element")
        let failure = value.associatedType(named: "Failure")
        let concreteFailure = value.concrete(ResultAssociatedFailure.self)
        let opaque = value.result(
            success: element,
            failure: concreteFailure
        )
        let opaqueFailure = value.result(
            success: value.array(of: value.concrete(Int.self)),
            failure: failure
        )
        let fixed = value.result(
            success: value.array(of: element),
            failure: concreteFailure
        )
        let set = value.result(
            success: value.set(
                of: value.optional(wrapping: element)
            ),
            failure: concreteFailure
        )
        let nested = value.optional(
            wrapping: value.dictionary(
                key: value.concrete(String.self),
                value: value.result(
                    success: value.optional(
                        wrapping: value.array(of: element)
                    ),
                    failure: concreteFailure
                )
            )
        )
        let stub = try ProbeStub(
            .method(opaque, returning: opaque),
            .method(opaqueFailure, returning: opaqueFailure),
            .method(fixed, returning: fixed),
            .method(set, returning: set),
            .method(nested, returning: nested)
        )

        #expect(
            stub.recorder.runtimeMethod(for: 0)?.returnConvention
                == .associatedType(name: "Element")
        )
        #expect(
            stub.recorder.runtimeMethod(for: 2)?.returnConvention == .concrete
        )

        stub.when(returning: Result<[Int], ResultAssociatedFailure>.success([])) {
            $0.transform(
                opaqueFailure: any(
                    using: Result<[Int], ResultAssociatedFailure>.success([])
                )
            )
        }.thenReturn(.success([7]))
        stub.when(
            returning: Result<Set<Int?>, ResultAssociatedFailure>.success([])
        ) {
            $0.transform(
                set: any(
                    using: Result<Set<Int?>, ResultAssociatedFailure>.success([])
                )
            )
        }.then {
            (value: Result<Set<Int?>, ResultAssociatedFailure>) in value
        }
        let probe:
            any ResultAssociatedTypeProbe<
                Int,
                ResultAssociatedFailure
            > = stub()
        #expect(
            probe.transform(opaqueFailure: .failure(.failed)) == .success([7])
        )
        #expect(probe.transform(set: .success([1, 2])) == .success([1, 2]))
    }

    @Test func explicitResultRequiresAnErrorFailureType() {
        typealias ProbeStub = Stub<any ExplicitResultValidationProbe<Int>>
        let value = ProbeStub.Requirement.Value.self
        let invalid = value.result(
            success: value.associatedType(named: "Element"),
            failure: value.concrete(String.self)
        )

        expectUnsupportedProtocolShape(containing: "does not conform to Error") {
            _ = try ProbeStub(.method(invalid, returning: invalid))
        }
    }

    @Test func automaticDiscoveryRejectsArbitraryGenericResultPayloads() {
        _ = useLinkedUnsupportedResultAssociatedTypeProbe(
            RealUnsupportedResultAssociatedTypeProbe()
        )

        expectUnsupportedProtocolShape(containing: "ResultAssociatedBox") {
            _ = try Stub<any UnsupportedResultAssociatedTypeProbe<Int>>()
        }
    }
}

private indirect enum ResultDependencyShape: Equatable {
    case independent
    case associatedType(String)
    case optional(Self)
    case array(Self)
    case set(Self)
    case dictionary(key: Self, value: Self)
    case result(success: Self, failure: Self)
}

private func resultDependencyShape(
    _ dependency: WitnessValueDependency
) -> ResultDependencyShape {
    switch dependency {
        case .independent:
            .independent
        case .associatedType(let reference):
            .associatedType(reference.name)
        case .optional(let wrapped):
            .optional(resultDependencyShape(wrapped))
        case .array(let element):
            .array(resultDependencyShape(element))
        case .set(let element):
            .set(resultDependencyShape(element))
        case .dictionary(let key, let value):
            .dictionary(
                key: resultDependencyShape(key),
                value: resultDependencyShape(value)
            )
        case .result(let success, let failure):
            .result(
                success: resultDependencyShape(success),
                failure: resultDependencyShape(failure)
            )
    }
}

private func assertResultDescriptor<Value>(
    _ method: MethodDescriptor,
    type: Value.Type,
    dependency: ResultDependencyShape,
    convention: WitnessValueConvention,
    isIndirect expectedIndirect: Bool,
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
        resultDependencyShape(argument.value.dependency) == dependency,
        sourceLocation: sourceLocation
    )
    #expect(
        resultDependencyShape(method.result.dependency) == dependency,
        sourceLocation: sourceLocation
    )
    #expect(argument.value.convention == convention, sourceLocation: sourceLocation)
    #expect(method.result.convention == convention, sourceLocation: sourceLocation)
    #expect(
        isIndirectLayout(argument.value.layout) == expectedIndirect,
        sourceLocation: sourceLocation
    )
    #expect(
        isIndirectLayout(method.result.layout) == expectedIndirect,
        sourceLocation: sourceLocation
    )
}

private func isIndirectLayout(_ layout: ABIClass) -> Bool {
    if case .indirect = layout { true } else { false }
}
