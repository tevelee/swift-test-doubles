import Testing
@testable import TestDoubles

// Runtime-discovery fixtures must remain module-internal so optimized tests
// continue to dispatch through their linked and fabricated witness tables.
protocol AsyncTypedThrowsRequirementProbe: Sendable {
    func load(_ mode: Int) async throws(TypedThrowsPayloadError) -> String
}

struct RealAsyncTypedThrowsRequirementProbe: AsyncTypedThrowsRequirementProbe {
    func load(_ mode: Int) async throws(TypedThrowsPayloadError) -> String {
        "linked:\(mode)"
    }
}

struct AsyncAssociatedTypedThrowsError: Error, Equatable {
    let code: Int
}

protocol AsyncAssociatedTypedThrowsProbe<Failure> {
    associatedtype Failure: Error
    func load(_ shouldFail: Bool) async throws(Failure) -> String
}

struct RealAsyncAssociatedTypedThrowsProbe: AsyncAssociatedTypedThrowsProbe {
    func load(_ shouldFail: Bool) async throws(AsyncAssociatedTypedThrowsError) -> String {
        "linked"
    }
}

protocol AsyncIndirectTypedErrorProbe {
    func load(_ shouldFail: Bool) async throws(IndirectTypedThrowsRequirementError) -> Int
}

struct RealAsyncIndirectTypedErrorProbe: AsyncIndirectTypedErrorProbe {
    func load(_ shouldFail: Bool) async throws(IndirectTypedThrowsRequirementError) -> Int {
        1
    }
}

protocol AsyncIndirectTypedResultProbe {
    func load(_ shouldFail: Bool) async throws(TypedThrowsPayloadError) -> IndirectTypedThrowsResult
}

struct RealAsyncIndirectTypedResultProbe: AsyncIndirectTypedResultProbe {
    func load(_ shouldFail: Bool) async throws(TypedThrowsPayloadError) -> IndirectTypedThrowsResult {
        IndirectTypedThrowsResult(first: 1, second: 2, third: 3, fourth: 4, fifth: 5)
    }
}

protocol AsyncSpilledTypedErrorBufferProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int
    ) async throws(IndirectTypedThrowsRequirementError) -> Int
}

protocol AsyncIndirectTypedErrorThreeArgumentProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int
}

struct RealAsyncIndirectTypedErrorThreeArgumentProbe:
    AsyncIndirectTypedErrorThreeArgumentProbe
{
    func load(
        _ first: Int,
        _ second: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int {
        first + second
    }
}

protocol AsyncIndirectTypedErrorFourArgumentProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int
}

struct RealAsyncIndirectTypedErrorFourArgumentProbe:
    AsyncIndirectTypedErrorFourArgumentProbe
{
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int {
        first + second + third
    }
}

private protocol AsyncIndirectTypedErrorFiveArgumentProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int
}

protocol AsyncIndirectTypedErrorSixArgumentProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int
}

struct RealAsyncIndirectTypedErrorSixArgumentProbe:
    AsyncIndirectTypedErrorSixArgumentProbe
{
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ shouldFail: Bool
    ) async throws(IndirectTypedThrowsRequirementError) -> Int {
        first + second + third + fourth + fifth
    }
}

struct RealAsyncSpilledTypedErrorBufferProbe: AsyncSpilledTypedErrorBufferProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int
    ) async throws(IndirectTypedThrowsRequirementError) -> Int {
        first + second + third + fourth + fifth + sixth + seventh + eighth
    }
}

private protocol ExplicitAsyncTypedThrowsProbe {
    func load(_ value: Int) async throws(TypedThrowsPayloadError) -> String
}

private protocol ExplicitAsyncTypedThrowsAssociatedProbe<Element> {
    associatedtype Element
    func load() async throws(TypedThrowsPayloadError) -> Element
}

private func callWithValue(
    _ stub: Stub<any AsyncTypedThrowsRequirementProbe>
) async throws(TypedThrowsPayloadError) {
    try await stub.withValue {
        _ async throws(TypedThrowsPayloadError) in
        throw TypedThrowsPayloadError(code: 42, message: "failed")
    }
}

@Suite struct AsyncTypedThrowsRequirementTests {
    @Test func directResultsAndErrorsSupportImmediateAndSuspendingHandlers() async throws {
        _ = RealAsyncTypedThrowsRequirementProbe()
        let stub = try Stub<any AsyncTypedThrowsRequirementProbe>()
        let method = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(method.isAsync)
        #expect(
            method.typedErrorType.map(ObjectIdentifier.init)
                == ObjectIdentifier(TypedThrowsPayloadError.self)
        )
        #expect(method.typedErrorUsesIndirectResultSlot == false)

        await stub.when { try await $0.load(equal(0)) }.thenReturn("immediate")
        await stub.when { try await $0.load(equal(1)) }.then {
            (_: Int) throws -> String in
            throw TypedThrowsPayloadError(code: 1, message: "immediate")
        }
        await stub.when { try await $0.load(equal(2)) }.then {
            (_: Int) async throws -> String in
            await Task.yield()
            return "suspending"
        }
        await stub.when { try await $0.load(equal(3)) }.then {
            (_: Int) async throws -> String in
            await Task.yield()
            throw TypedThrowsPayloadError(code: 3, message: "suspending")
        }

        let probe = stub()
        #expect(try await probe.load(0) == "immediate")
        let immediateError = await #expect(throws: TypedThrowsPayloadError.self) {
            _ = try await probe.load(1)
        }
        #expect(immediateError == TypedThrowsPayloadError(code: 1, message: "immediate"))
        #expect(try await probe.load(2) == "suspending")
        let suspendingError = await #expect(throws: TypedThrowsPayloadError.self) {
            _ = try await probe.load(3)
        }
        #expect(suspendingError == TypedThrowsPayloadError(code: 3, message: "suspending"))
    }

    @Test func directAssociatedTypedErrorsUseIndirectStorageAcrossSuspension() async throws {
        _ = RealAsyncAssociatedTypedThrowsProbe()
        typealias Probe = any AsyncAssociatedTypedThrowsProbe<
            AsyncAssociatedTypedThrowsError
        >
        let stub = try Stub<Probe>()
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(method.isAsync)
        #expect(
            method.typedErrorType.map(ObjectIdentifier.init)
                == ObjectIdentifier(AsyncAssociatedTypedThrowsError.self)
        )
        #expect(method.typedErrorDependency == .associatedType(name: "Failure"))
        #expect(method.typedErrorUsesIndirectResultSlot)

        await stub.when { try await $0.load(equal(false)) }.thenReturn("loaded")
        await stub.when { try await $0.load(equal(true)) }.then {
            (_: Bool) async throws -> String in
            await Task.yield()
            throw AsyncAssociatedTypedThrowsError(code: 42)
        }
        let probe: Probe = stub()

        #expect(try await probe.load(false) == "loaded")
        let error = await #expect(throws: AsyncAssociatedTypedThrowsError.self) {
            _ = try await probe.load(true)
        }
        #expect(error == AsyncAssociatedTypedThrowsError(code: 42))
    }

    @Test func indirectResultsAndErrorsUseDistinctCallerStorage() async throws {
        _ = RealAsyncIndirectTypedErrorProbe()
        _ = RealAsyncIndirectTypedResultProbe()

        let indirectError = try Stub<any AsyncIndirectTypedErrorProbe>()
        let errorMethod = try #require(indirectError.recorder.runtimeMethod(for: 0))
        #expect(errorMethod.typedErrorUsesIndirectResultSlot)
        await indirectError.when { try await $0.load(equal(false)) }.thenReturn(42)
        await indirectError.when { try await $0.load(equal(true)) }.then {
            (_: Bool) async throws -> Int in
            await Task.yield()
            throw IndirectTypedThrowsRequirementError(
                first: 1,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
        #expect(try await indirectError().load(false) == 42)
        let largeError = await #expect(throws: IndirectTypedThrowsRequirementError.self) {
            _ = try await indirectError().load(true)
        }
        #expect(
            largeError
                == IndirectTypedThrowsRequirementError(
                    first: 1,
                    second: 2,
                    third: 3,
                    fourth: 4,
                    fifth: 5
                )
        )

        let indirectResult = try Stub<any AsyncIndirectTypedResultProbe>()
        let resultMethod = try #require(indirectResult.recorder.runtimeMethod(for: 0))
        #expect(resultMethod.typedErrorUsesIndirectResultSlot)
        let expected = IndirectTypedThrowsResult(
            first: 5,
            second: 4,
            third: 3,
            fourth: 2,
            fifth: 1
        )
        await indirectResult.when { try await $0.load(equal(false)) }.then {
            (_: Bool) async throws -> IndirectTypedThrowsResult in
            await Task.yield()
            return expected
        }
        await indirectResult.when { try await $0.load(equal(true)) }.then {
            (_: Bool) async throws -> IndirectTypedThrowsResult in
            await Task.yield()
            throw TypedThrowsPayloadError(code: 42, message: "failed")
        }
        #expect(try await indirectResult().load(false) == expected)
        let directError = await #expect(throws: TypedThrowsPayloadError.self) {
            _ = try await indirectResult().load(true)
        }
        #expect(directError == TypedThrowsPayloadError(code: 42, message: "failed"))
    }

    @Test func typedErrorBuffersBeyondOneSpilledWordFailClosed() async throws {
        _ = RealAsyncSpilledTypedErrorBufferProbe()
        #if arch(x86_64)
            #expect(throws: StubError.self) {
                _ = try Stub<any AsyncSpilledTypedErrorBufferProbe>()
            }
        #else
            let stub = try Stub<any AsyncSpilledTypedErrorBufferProbe>()
            await stub.when {
                try await $0.load(
                    any(), any(), any(), any(), any(), any(), any(), any()
                )
            }.thenReturn(36)
            #expect(try await stub().load(1, 2, 3, 4, 5, 6, 7, 8) == 36)
        #endif
    }

    @Test func indirectTypedErrorRegisterBoundariesIncludeHiddenStorage() {
        func method(argumentCount: Int) -> MethodDescriptor {
            MethodDescriptor(
                kind: .method,
                name: "load",
                index: 0,
                argumentTypes: Array(repeating: Int.self, count: argumentCount),
                returnType: Int.self,
                typedErrorType: IndirectTypedThrowsRequirementError.self,
                isThrowing: true,
                isAsync: true
            )
        }

        let firstX86Spill = method(argumentCount: 6)
        let secondX86Spill = method(argumentCount: 7)
        let firstArmSpill = method(argumentCount: 8)
        let secondArmSpill = method(argumentCount: 9)

        #expect(firstX86Spill.typedErrorUsesIndirectResultSlot)
        #expect(unsupportedRuntimeReason(for: firstX86Spill, architecture: .x86_64) == nil)
        #expect(unsupportedRuntimeReason(for: secondX86Spill, architecture: .x86_64) != nil)
        #expect(unsupportedRuntimeReason(for: firstArmSpill, architecture: .arm64) == nil)
        #expect(unsupportedRuntimeReason(for: secondArmSpill, architecture: .arm64) != nil)
    }

    @Test func directTypedErrorsDoNotConsumeHiddenRegisterStorage() {
        func method(argumentCount: Int) -> MethodDescriptor {
            MethodDescriptor(
                kind: .method,
                name: "load",
                index: 0,
                argumentTypes: Array(repeating: Int.self, count: argumentCount),
                returnType: Int.self,
                typedErrorType: TypedThrowsRequirementError.self,
                isThrowing: true,
                isAsync: true
            )
        }

        let firstX86Spill = method(argumentCount: 7)
        let secondX86Spill = method(argumentCount: 8)
        let firstArmSpill = method(argumentCount: 9)
        let secondArmSpill = method(argumentCount: 10)

        #expect(firstX86Spill.typedErrorUsesIndirectResultSlot == false)
        #expect(unsupportedRuntimeReason(for: firstX86Spill, architecture: .x86_64) == nil)
        #expect(unsupportedRuntimeReason(for: secondX86Spill, architecture: .x86_64) != nil)
        #expect(unsupportedRuntimeReason(for: firstArmSpill, architecture: .arm64) == nil)
        #expect(unsupportedRuntimeReason(for: secondArmSpill, architecture: .arm64) != nil)
    }

    @Test func supportedIndirectTypedErrorBoundaryReturnsAndThrows() async throws {
        let expectedError = IndirectTypedThrowsRequirementError(
            first: 1,
            second: 2,
            third: 3,
            fourth: 4,
            fifth: 5
        )

        #if arch(x86_64)
            _ = RealAsyncIndirectTypedErrorThreeArgumentProbe()
            let stub = try Stub<any AsyncIndirectTypedErrorThreeArgumentProbe>()
            await stub.when {
                try await $0.load(any(), any(), equal(false))
            }.thenReturn(3)
            await stub.when {
                try await $0.load(any(), any(), equal(true))
            }.thenThrow(expectedError)
            #expect(try await stub().load(1, 2, false) == 3)
            let error = await #expect(throws: IndirectTypedThrowsRequirementError.self) {
                _ = try await stub().load(1, 2, true)
            }
        #else
            let stub = try Stub<any AsyncIndirectTypedErrorFiveArgumentProbe>(
                .method(
                    Int.self, Int.self, Int.self, Int.self, Bool.self,
                    returning: Int.self,
                    throwing: IndirectTypedThrowsRequirementError.self,
                    isAsync: true
                )
            )
            await stub.when {
                try await $0.load(any(), any(), any(), any(), equal(false))
            }.thenReturn(10)
            await stub.when {
                try await $0.load(any(), any(), any(), any(), equal(true))
            }.thenThrow(expectedError)
            #expect(try await stub().load(1, 2, 3, 4, false) == 10)
            let error = await #expect(throws: IndirectTypedThrowsRequirementError.self) {
                _ = try await stub().load(1, 2, 3, 4, true)
            }
        #endif

        #expect(error == expectedError)
    }

    @Test func formerlyReservedTypedErrorRegisterBoundaryIsSupported() async throws {
        #if arch(x86_64)
            _ = RealAsyncIndirectTypedErrorFourArgumentProbe()
            let stub = try Stub<any AsyncIndirectTypedErrorFourArgumentProbe>()
            await stub.when {
                try await $0.load(any(), any(), any(), equal(false))
            }.thenReturn(6)
            #expect(try await stub().load(1, 2, 3, false) == 6)
        #else
            _ = RealAsyncIndirectTypedErrorSixArgumentProbe()
            let stub = try Stub<any AsyncIndirectTypedErrorSixArgumentProbe>()
            await stub.when {
                try await $0.load(any(), any(), any(), any(), any(), equal(false))
            }.thenReturn(15)
            #expect(try await stub().load(1, 2, 3, 4, 5, false) == 15)
        #endif
    }

    @MainActor
    @Test func suspendingTypedHandlersPreserveTheirCreationExecutor() async throws {
        _ = RealAsyncTypedThrowsRequirementProbe()
        let stub = try Stub<any AsyncTypedThrowsRequirementProbe>()
        await stub.when { try await $0.load(any()) }.then {
            (_: Int) async throws -> String in
            MainActor.preconditionIsolated()
            await Task.yield()
            MainActor.preconditionIsolated()
            throw TypedThrowsPayloadError(code: 9, message: "main actor")
        }

        let error = await #expect(throws: TypedThrowsPayloadError.self) {
            _ = try await stub().load(9)
        }
        #expect(error == TypedThrowsPayloadError(code: 9, message: "main actor"))
        MainActor.preconditionIsolated()
    }

    @Test func explicitAsyncTypedThrowsDoNotNeedALinkedConformer() async throws {
        let stub = try Stub<any ExplicitAsyncTypedThrowsProbe>(
            .method(
                Int.self,
                returning: String.self,
                throwing: TypedThrowsPayloadError.self,
                isAsync: true
            )
        )
        await stub.when { try await $0.load(equal(1)) }.thenReturn("loaded")
        #expect(try await stub().load(1) == "loaded")

        typealias AssociatedStub =
            Stub<any ExplicitAsyncTypedThrowsAssociatedProbe<Int>>
        let element = AssociatedStub.Requirement.Value.associatedType(
            named: "Element"
        )
        let associated = try AssociatedStub(
            .method(
                returning: element,
                throwing: TypedThrowsPayloadError.self,
                isAsync: true
            )
        )
        await associated.when { try await $0.load() }.thenReturn(42)
        #expect(try await associated().load() == 42)
    }

    @Test func withValuePreservesTypedErrors() async throws {
        let stub = try Stub<any AsyncTypedThrowsRequirementProbe>()

        let error = await #expect(throws: TypedThrowsPayloadError.self) {
            try await callWithValue(stub)
        }
        #expect(error == TypedThrowsPayloadError(code: 42, message: "failed"))
    }
}
