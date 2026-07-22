import TestDoublesFixtures
import Testing
@testable import TestDoubles

@inline(never)
private func useLinkedAssociatedClassTypedErrorProbe(
    _ probe: any ExternalAssociatedClassTypedErrorProbe<Int>
) -> Int {
    (try? probe.oneParameter(0)) ?? -1
}

@Suite struct AssociatedGenericClassTypedErrorTests {
    @Test func automaticDiscoveryReconstructsClassErrorMetadata() throws {
        #expect(
            useLinkedAssociatedClassTypedErrorProbe(
                RealExternalAssociatedClassTypedErrorProbe()
            ) == 10
        )
        let stub = try Stub<
            any ExternalAssociatedClassTypedErrorProbe<Int>
        >()

        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedClassError<Int>.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedClassError",
                [.associatedType("Element")]
            )
        )
        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedPairClassError<Int, String>.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedPairClassError",
                [.associatedType("Element"), .independent]
            )
        )
        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 2)),
            type: ExternalAssociatedPairClassError<
                ExternalAssociatedClassError<Int>,
                String
            >.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedPairClassError",
                [
                    .genericClass(
                        "TestDoublesFixtures.ExternalAssociatedClassError",
                        [.associatedType("Element")]
                    ),
                    .independent
                ]
            )
        )
        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 3)),
            type: ExternalAssociatedClassError<Int>.self,
            dependency: .genericClass(
                "TestDoublesFixtures.ExternalAssociatedClassError",
                [.associatedType("Element")]
            )
        )
    }

    @Test func synchronousClassErrorsPreserveMatchingAndDynamicType() throws {
        typealias Probe = any ExternalAssociatedClassTypedErrorProbe<Int>
        let stub = try Stub<Probe>()
        stub.when { try $0.oneParameter(equal(0)) }.thenReturn(100)
        stub.when { try $0.oneParameter(equal(1)) }.thenThrow(
            ExternalAssociatedClassError(101)
        )
        let probe: Probe = stub()

        #expect(try probe.oneParameter(0) == 100)
        let thrownError = #expect(throws: ExternalAssociatedClassError<Int>.self) {
            _ = try probe.oneParameter(1)
        }
        let error = try #require(thrownError)
        #expect(
            ObjectIdentifier(Swift.type(of: error))
                == ObjectIdentifier(ExternalAssociatedClassError<Int>.self)
        )
        #expect(error.value == 101)
        stub.verify { try $0.oneParameter(equal(0)) }
        stub.verify { try $0.oneParameter(equal(1)) }
    }

    @Test func pairAndNestedClassErrorsPreservePayloads() throws {
        typealias Probe = any ExternalAssociatedClassTypedErrorProbe<Int>
        let stub = try Stub<Probe>()
        stub.when { try $0.twoParameters(equal(0)) }.thenReturn("success")
        stub.when { try $0.twoParameters(equal(2)) }.thenThrow(
            ExternalAssociatedPairClassError(202, "pair")
        )
        stub.when { try $0.nestedClass(equal(0)) }.thenReturn(300)
        stub.when { try $0.nestedClass(equal(3)) }.thenThrow(
            ExternalAssociatedPairClassError(
                ExternalAssociatedClassError(303),
                "nested"
            )
        )
        let probe: Probe = stub()

        #expect(try probe.twoParameters(0) == "success")
        let thrownPair = #expect(
            throws: ExternalAssociatedPairClassError<Int, String>.self
        ) {
            _ = try probe.twoParameters(2)
        }
        let pair = try #require(thrownPair)
        #expect(
            ObjectIdentifier(Swift.type(of: pair))
                == ObjectIdentifier(
                    ExternalAssociatedPairClassError<Int, String>.self
                )
        )
        #expect(pair.first == 202)
        #expect(pair.second == "pair")

        #expect(try probe.nestedClass(0) == 300)
        typealias NestedError = ExternalAssociatedPairClassError<
            ExternalAssociatedClassError<Int>,
            String
        >
        let thrownNested = #expect(throws: NestedError.self) {
            _ = try probe.nestedClass(3)
        }
        let nested = try #require(thrownNested)
        #expect(ObjectIdentifier(Swift.type(of: nested)) == ObjectIdentifier(NestedError.self))
        #expect(nested.first.value == 303)
        #expect(nested.second == "nested")
    }

    @Test func asynchronousClassErrorsPreserveSuccessAndFailure() async throws {
        typealias Probe = any ExternalAssociatedClassTypedErrorProbe<Int>
        let stub = try Stub<Probe>()
        await stub.when { try await $0.asynchronous(equal(0)) }.thenReturn("success")
        await stub.when { try await $0.asynchronous(equal(4)) }.then {
            (_: Int) async throws -> String in
            await Task.yield()
            throw ExternalAssociatedClassError(404)
        }
        let probe: Probe = stub()

        #expect(try await probe.asynchronous(0) == "success")
        let thrownError = await #expect(throws: ExternalAssociatedClassError<Int>.self) {
            _ = try await probe.asynchronous(4)
        }
        let error = try #require(thrownError)
        #expect(
            ObjectIdentifier(Swift.type(of: error))
                == ObjectIdentifier(ExternalAssociatedClassError<Int>.self)
        )
        #expect(error.value == 404)
        await stub.verify { try await $0.asynchronous(equal(0)) }
        await stub.verify { try await $0.asynchronous(equal(4)) }
    }

    @Test func explicitSchemasCannotEraseClassErrorDependency() {
        _ = RealExternalExplicitAssociatedClassTypedErrorProbe()
        typealias ProbeStub = Stub<
            any ExternalExplicitAssociatedClassTypedErrorProbe<Int>
        >

        expectStubError {
            _ = try ProbeStub(
                .method(
                    returning: Int.self,
                    throwing: ExternalAssociatedClassError<Int>.self
                )
            )
        } matching: { error in
            guard case .requirementMismatch(_, let index, let expected, let actual) = error
            else {
                return false
            }
            return index == 0
                && expected.contains("associated-dependent generic class")
                && actual.contains("associated-dependent generic class") == false
        }

        _ = RealExternalStringlyAssociatedClassTypedErrorProbe()
        typealias StringlyStub = Stub<
            any ExternalStringlyAssociatedClassTypedErrorProbe<
                ExternalAssociatedLeafError
            >
        >
        let result = StringlyStub.Requirement.Value.concrete(Int.self)
        expectStubError {
            _ = try StringlyStub(
                .method(
                    returning: result,
                    throwingAssociatedTypeNamed: "Failure"
                )
            )
        } matching: { error in
            guard case .requirementMismatch(_, let index, let expected, let actual) = error
            else {
                return false
            }
            return index == 0
                && expected.contains("associated-dependent generic class")
                && actual.contains("associated Failure")
        }
    }

    @Test func valueWrappedStructAndEnumErrorsRemainUnsupported() {
        _ = RealExternalOptionalAssociatedClassErrorProbe()
        _ = RealExternalValueWrappedAssociatedClassErrorProbe()
        _ = RealExternalGenericStructAssociatedErrorProbe()
        _ = RealExternalGenericEnumAssociatedErrorProbe()

        let operations: [() throws -> Void] = [
            {
                _ = try Stub<
                    any ExternalOptionalAssociatedClassErrorProbe<Int>
                >()
            },
            {
                _ = try Stub<
                    any ExternalValueWrappedAssociatedClassErrorProbe<Int>
                >()
            },
            {
                _ = try Stub<
                    any ExternalGenericStructAssociatedErrorProbe<Int>
                >()
            },
            {
                _ = try Stub<
                    any ExternalGenericEnumAssociatedErrorProbe<Int>
                >()
            }
        ]
        for operation in operations {
            expectUnsupportedProtocolShape(
                containing: "Optional and other value wrappers"
            ) {
                try operation()
            }
        }
    }
}

private indirect enum AssociatedClassErrorDependencyShape: Equatable {
    case independent
    case associatedType(String)
    case genericClass(String, [Self])
}

private func associatedClassErrorDependencyShape(
    _ dependency: WitnessValueDependency
) -> AssociatedClassErrorDependencyShape? {
    switch dependency {
        case .independent:
            return .independent
        case .associatedType(let reference):
            return .associatedType(reference.name)
        case .genericClass(let constructor, let arguments):
            if arguments.isEmpty {
                return .genericClass(constructor.name, [])
            }
            var resolved: [AssociatedClassErrorDependencyShape] = []
            resolved.reserveCapacity(arguments.count)
            for argument in arguments {
                guard let shape = associatedClassErrorDependencyShape(argument)
                else {
                    return nil
                }
                resolved.append(shape)
            }
            return .genericClass(constructor.name, resolved)
        case .optional, .array, .set, .dictionary, .result:
            return nil
    }
}

private func assertTypedError<Failure: Error>(
    _ method: MethodDescriptor,
    type: Failure.Type,
    dependency: AssociatedClassErrorDependencyShape,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let errorType = try #require(
        method.typedErrorType,
        sourceLocation: sourceLocation
    )
    #expect(
        ObjectIdentifier(errorType) == ObjectIdentifier(type),
        sourceLocation: sourceLocation
    )
    #expect(
        associatedClassErrorDependencyShape(method.typedErrorDependency)
            == dependency,
        sourceLocation: sourceLocation
    )
    #expect(
        method.typedErrorUsesIndirectResultSlot == false,
        sourceLocation: sourceLocation
    )
}
