import InternalRuntimeContract
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
            associatedTypeNames: ["Element"]
        )
        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedPairClassError<Int, String>.self,
            associatedTypeNames: ["Element"]
        )
        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 2)),
            type: ExternalAssociatedPairClassError<
                ExternalAssociatedClassError<Int>,
                String
            >.self,
            associatedTypeNames: ["Element"]
        )
        try assertTypedError(
            #require(stub.recorder.runtimeMethod(for: 3)),
            type: ExternalAssociatedClassError<Int>.self,
            associatedTypeNames: ["Element"]
        )
    }

    @Test func synchronousClassErrorsPreserveMatchingAndDynamicType() throws {
        typealias Probe = any ExternalAssociatedClassTypedErrorProbe<Int>
        let stub = try Stub<Probe>()
        stub.onCall { try $0.oneParameter(Match.equal(0)) }.thenReturn(100)
        stub.onCall { try $0.oneParameter(Match.equal(1)) }.thenThrow(
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
        stub.verify { try $0.oneParameter(Match.equal(0)) }
        stub.verify { try $0.oneParameter(Match.equal(1)) }
    }

    @Test func constrainedClassErrorsPreserveMatchingAndDynamicType() throws {
        typealias Probe = any ExternalConstrainedAssociatedClassTypedErrorProbe<Int>
        let stub = try Stub<Probe>()
        stub.onCall { try $0.load(Match.equal(0)) }.thenReturn(100)
        stub.onCall { try $0.load(Match.equal(1)) }.thenThrow(
            ExternalConstrainedAssociatedClassError(101)
        )
        let probe: Probe = stub()

        #expect(try probe.load(0) == 100)
        let thrownError = #expect(
            throws: ExternalConstrainedAssociatedClassError<Int>.self
        ) {
            _ = try probe.load(1)
        }
        let error = try #require(thrownError)
        #expect(
            ObjectIdentifier(Swift.type(of: error))
                == ObjectIdentifier(
                    ExternalConstrainedAssociatedClassError<Int>.self
                )
        )
        #expect(error.value == 101)
        stub.verify { try $0.load(Match.equal(0)) }
        stub.verify { try $0.load(Match.equal(1)) }
    }

    @Test func pairAndNestedClassErrorsPreservePayloads() throws {
        typealias Probe = any ExternalAssociatedClassTypedErrorProbe<Int>
        let stub = try Stub<Probe>()
        stub.onCall { try $0.twoParameters(Match.equal(0)) }.thenReturn("success")
        stub.onCall { try $0.twoParameters(Match.equal(2)) }.thenThrow(
            ExternalAssociatedPairClassError(202, "pair")
        )
        stub.onCall { try $0.nestedClass(Match.equal(0)) }.thenReturn(300)
        stub.onCall { try $0.nestedClass(Match.equal(3)) }.thenThrow(
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
        await stub.onCall { try await $0.asynchronous(Match.equal(0)) }.thenReturn("success")
        await stub.onCall { try await $0.asynchronous(Match.equal(4)) }.then {
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
        await stub.verify { try await $0.asynchronous(Match.equal(0)) }
        await stub.verify { try await $0.asynchronous(Match.equal(4)) }
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

    @Test func genericStructAndEnumErrorsPreserveSyncAndAsyncPayloads() async throws {
        _ = RealExternalGenericStructAssociatedErrorProbe()
        _ = RealExternalGenericEnumAssociatedErrorProbe()

        typealias StructProbe = any ExternalGenericStructAssociatedErrorProbe<Int>
        let structStub = try Stub<StructProbe>()
        try assertTypedError(
            #require(structStub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedGenericStructError<Int>.self,
            associatedTypeNames: ["Element"]
        )
        try assertTypedError(
            #require(structStub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedGenericStructError<Int>.self,
            associatedTypeNames: ["Element"]
        )
        structStub.onCall { try $0.load() }.thenThrow(
            ExternalAssociatedGenericStructError(101)
        )
        await structStub.onCall { try await $0.asynchronouslyLoad(Match.equal(2)) }.then {
            (_: Int) async throws -> Int in
            await Task.yield()
            throw ExternalAssociatedGenericStructError(102)
        }
        let structProbe: StructProbe = structStub()

        let thrownStruct = #expect(
            throws: ExternalAssociatedGenericStructError<Int>.self
        ) {
            _ = try structProbe.load()
        }
        #expect(try #require(thrownStruct).value == 101)
        let thrownAsyncStruct = await #expect(
            throws: ExternalAssociatedGenericStructError<Int>.self
        ) {
            _ = try await structProbe.asynchronouslyLoad(2)
        }
        #expect(try #require(thrownAsyncStruct).value == 102)

        typealias EnumProbe = any ExternalGenericEnumAssociatedErrorProbe<Int>
        let enumStub = try Stub<EnumProbe>()
        try assertTypedError(
            #require(enumStub.recorder.runtimeMethod(for: 0)),
            type: ExternalAssociatedGenericEnumError<Int>.self,
            associatedTypeNames: ["Element"]
        )
        try assertTypedError(
            #require(enumStub.recorder.runtimeMethod(for: 1)),
            type: ExternalAssociatedGenericEnumError<Int>.self,
            associatedTypeNames: ["Element"]
        )
        enumStub.onCall { try $0.load() }.thenThrow(
            ExternalAssociatedGenericEnumError<Int>.value(201)
        )
        await enumStub.onCall { try await $0.asynchronouslyLoad(Match.equal(2)) }.then {
            (_: Int) async throws -> Int in
            await Task.yield()
            throw ExternalAssociatedGenericEnumError.value(202)
        }
        let enumProbe: EnumProbe = enumStub()

        let thrownEnum = #expect(
            throws: ExternalAssociatedGenericEnumError<Int>.self
        ) {
            _ = try enumProbe.load()
        }
        guard case .value(let syncEnumValue) = try #require(thrownEnum) else {
            Issue.record("Expected the generic enum error's value case.")
            return
        }
        #expect(syncEnumValue == 201)
        let thrownAsyncEnum = await #expect(
            throws: ExternalAssociatedGenericEnumError<Int>.self
        ) {
            _ = try await enumProbe.asynchronouslyLoad(2)
        }
        guard case .value(let asyncEnumValue) = try #require(thrownAsyncEnum) else {
            Issue.record("Expected the generic enum error's value case.")
            return
        }
        #expect(asyncEnumValue == 202)

        typealias WrappedClassProbe = any ExternalValueWrappedAssociatedClassErrorProbe<Int>
        let wrappedClassStub = try Stub<WrappedClassProbe>()
        wrappedClassStub.onCall { try $0.load() }.thenThrow(
            ExternalAssociatedClassError(ExternalAssociatedErrorValue(303))
        )
        let wrappedClassProbe: WrappedClassProbe = wrappedClassStub()
        let thrownWrappedClass = #expect(
            throws: ExternalAssociatedClassError<ExternalAssociatedErrorValue<Int>>.self
        ) {
            _ = try wrappedClassProbe.load()
        }
        #expect(try #require(thrownWrappedClass).value.value == 303)

        structStub.verify { try $0.load() }
        await structStub.verify { try await $0.asynchronouslyLoad(Match.equal(2)) }
        enumStub.verify { try $0.load() }
        await enumStub.verify { try await $0.asynchronouslyLoad(Match.equal(2)) }
    }

    @Test func optionalErrorsRemainUnsupported() {
        _ = RealExternalOptionalAssociatedClassErrorProbe()

        let operations: [() throws -> Void] = [
            {
                _ = try Stub<
                    any ExternalOptionalAssociatedClassErrorProbe<Int>
                >()
            }
        ]
        for operation in operations {
            expectUnsupportedProtocolShape(
                containing: "Optional and other unproven value wrappers"
            ) {
                try operation()
            }
        }
    }
}

private func assertTypedError<Failure: Error>(
    _ method: RuntimeMethod,
    type: Failure.Type,
    associatedTypeNames: [String],
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
        method.typedErrorAssociatedTypeUse?.names == associatedTypeNames,
        sourceLocation: sourceLocation
    )
}
