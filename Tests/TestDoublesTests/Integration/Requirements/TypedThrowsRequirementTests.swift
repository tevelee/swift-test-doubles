import Testing
@testable import TestDoubles

enum TypedThrowsRequirementError: Error, Equatable {
    case failed
}

protocol TypedThrowsRequirementProbe {
    func load() throws(TypedThrowsRequirementError) -> Int
}

struct RealTypedThrowsRequirementProbe: TypedThrowsRequirementProbe {
    func load() throws(TypedThrowsRequirementError) -> Int { 1 }
}

struct TypedThrowsPayloadError: Error, Equatable {
    let code: Int
    let message: String
}

protocol TypedThrowsPayloadProbe {
    func load(_ shouldFail: Bool) throws(TypedThrowsPayloadError) -> String
}

struct RealTypedThrowsPayloadProbe: TypedThrowsPayloadProbe {
    func load(_ shouldFail: Bool) throws(TypedThrowsPayloadError) -> String {
        if shouldFail {
            throw TypedThrowsPayloadError(code: 1, message: "linked")
        }
        return "linked"
    }
}

struct IndirectTypedThrowsRequirementError: Error, Equatable {
    let first: Int
    let second: Int
    let third: Int
    let fourth: Int
    let fifth: Int
}

protocol IndirectTypedThrowsRequirementProbe {
    func load(_ shouldFail: Bool) throws(IndirectTypedThrowsRequirementError) -> Int
}

struct RealIndirectTypedThrowsRequirementProbe:
    IndirectTypedThrowsRequirementProbe
{
    func load(_ shouldFail: Bool) throws(IndirectTypedThrowsRequirementError) -> Int { 1 }
}

struct IndirectTypedThrowsResult: Equatable {
    let first: Int
    let second: Int
    let third: Int
    let fourth: Int
    let fifth: Int
}

protocol IndirectTypedThrowsResultProbe {
    func load(_ shouldFail: Bool) throws(TypedThrowsRequirementError) -> IndirectTypedThrowsResult
}

struct RealIndirectTypedThrowsResultProbe: IndirectTypedThrowsResultProbe {
    func load(_ shouldFail: Bool) throws(TypedThrowsRequirementError) -> IndirectTypedThrowsResult {
        IndirectTypedThrowsResult(first: 1, second: 2, third: 3, fourth: 4, fifth: 5)
    }
}

protocol SpilledTypedErrorBufferProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int
    ) throws(IndirectTypedThrowsRequirementError) -> Int
}

struct RealSpilledTypedErrorBufferProbe: SpilledTypedErrorBufferProbe {
    func load(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int
    ) throws(IndirectTypedThrowsRequirementError) -> Int {
        first + second + third + fourth + fifth + sixth + seventh + eighth
    }
}

private protocol ExplicitTypedThrowsProbe {
    func load(_ value: Int) throws(TypedThrowsPayloadError) -> String
}

private protocol ExplicitTypedThrowsAssociatedProbe<Element> {
    associatedtype Element
    func load() throws(TypedThrowsRequirementError) -> Element
}

private enum OtherTypedThrowsRequirementError: Error {
    case failed
}

private func callWithValue(
    _ stub: Stub<any TypedThrowsRequirementProbe>
) throws(TypedThrowsRequirementError) {
    try stub.withValue { _ throws(TypedThrowsRequirementError) in
        throw .failed
    }
}

@Suite struct TypedThrowsRequirementTests {
    @Test func directConcreteTypedThrowsPropagateResultsAndErrors() throws {
        _ = RealTypedThrowsRequirementProbe()
        let success = try Stub<any TypedThrowsRequirementProbe>()
        let method = try #require(success.recorder.runtimeMethod(for: 0))
        #expect(
            method.typedErrorType.map(ObjectIdentifier.init)
                == ObjectIdentifier(TypedThrowsRequirementError.self)
        )
        success.when { try $0.load() }.thenReturn(42)
        #expect(try success().load() == 42)

        let failure = try Stub<any TypedThrowsRequirementProbe>()
        failure.when { try $0.load() }.thenThrow(TypedThrowsRequirementError.failed)
        #expect(throws: TypedThrowsRequirementError.failed) {
            _ = try failure().load()
        }

        #expect(throws: StubError.self) {
            _ = try Stub<any TypedThrowsRequirementProbe>(
                .method(returning: Int.self, isThrowing: true)
            )
        }
    }

    @Test func aggregateTypedErrorsUseDirectErrorResultRegisters() throws {
        _ = RealTypedThrowsPayloadProbe()
        let stub = try Stub<any TypedThrowsPayloadProbe>()
        stub.when { try $0.load(equal(false)) }.thenReturn("loaded")
        stub.when { try $0.load(equal(true)) }.then {
            (_: Bool) throws -> String in
            throw TypedThrowsPayloadError(code: 42, message: "failed")
        }

        let probe = stub()

        #expect(try probe.load(false) == "loaded")
        let error = #expect(throws: TypedThrowsPayloadError.self) {
            _ = try probe.load(true)
        }
        #expect(error == TypedThrowsPayloadError(code: 42, message: "failed"))
    }

    @Test func indirectTypedThrowsUseCallerProvidedErrorStorage() throws {
        _ = RealIndirectTypedThrowsRequirementProbe()
        _ = RealIndirectTypedThrowsResultProbe()

        let indirectError = try Stub<any IndirectTypedThrowsRequirementProbe>()
        let errorMethod = try #require(indirectError.recorder.runtimeMethod(for: 0))
        #expect(errorMethod.typedErrorUsesIndirectResultSlot)
        indirectError.when { try $0.load(equal(false)) }.thenReturn(42)
        indirectError.when { try $0.load(equal(true)) }.then {
            (_: Bool) throws -> Int in
            throw IndirectTypedThrowsRequirementError(
                first: 1,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
        #expect(try indirectError().load(false) == 42)
        let error = #expect(throws: IndirectTypedThrowsRequirementError.self) {
            _ = try indirectError().load(true)
        }
        #expect(
            error
                == IndirectTypedThrowsRequirementError(
                    first: 1,
                    second: 2,
                    third: 3,
                    fourth: 4,
                    fifth: 5
                )
        )

        let indirectResult = try Stub<any IndirectTypedThrowsResultProbe>()
        let resultMethod = try #require(indirectResult.recorder.runtimeMethod(for: 0))
        #expect(resultMethod.typedErrorUsesIndirectResultSlot)
        let expected = IndirectTypedThrowsResult(
            first: 1,
            second: 2,
            third: 3,
            fourth: 4,
            fifth: 5
        )
        indirectResult.when { try $0.load(equal(false)) }.thenReturn(expected)
        indirectResult.when { try $0.load(equal(true)) }.then {
            (_: Bool) throws -> IndirectTypedThrowsResult in
            throw TypedThrowsRequirementError.failed
        }
        #expect(try indirectResult().load(false) == expected)
        #expect(throws: TypedThrowsRequirementError.failed) {
            _ = try indirectResult().load(true)
        }

        _ = RealSpilledTypedErrorBufferProbe()
        let spilled = try Stub<any SpilledTypedErrorBufferProbe>()
        spilled.when { try $0.load(1, 2, 3, 4, 5, 6, 7, 8) }.then {
            (
                _: Int,
                _: Int,
                _: Int,
                _: Int,
                _: Int,
                _: Int,
                _: Int,
                _: Int
            ) throws -> Int in
            throw IndirectTypedThrowsRequirementError(
                first: 8,
                second: 7,
                third: 6,
                fourth: 5,
                fifth: 4
            )
        }
        let spilledError = #expect(throws: IndirectTypedThrowsRequirementError.self) {
            _ = try spilled().load(1, 2, 3, 4, 5, 6, 7, 8)
        }
        #expect(
            spilledError
                == IndirectTypedThrowsRequirementError(
                    first: 8,
                    second: 7,
                    third: 6,
                    fourth: 5,
                    fifth: 4
                )
        )
    }

    @Test func explicitTypedThrowsDoNotNeedALinkedConformer() throws {
        let success = try Stub<any ExplicitTypedThrowsProbe>(
            .method(
                Int.self,
                returning: String.self,
                throwing: TypedThrowsPayloadError.self
            )
        )
        success.when { try $0.load(equal(1)) }.thenReturn("loaded")
        #expect(try success().load(1) == "loaded")

        let failure = try Stub<any ExplicitTypedThrowsProbe>(
            .method(
                Int.self,
                returning: String.self,
                throwing: TypedThrowsPayloadError.self
            )
        )
        failure.when { try $0.load(equal(2)) }.then {
            (_: Int) throws -> String in
            throw TypedThrowsPayloadError(code: 42, message: "failed")
        }
        let error = #expect(throws: TypedThrowsPayloadError.self) {
            _ = try failure().load(2)
        }
        #expect(error == TypedThrowsPayloadError(code: 42, message: "failed"))

        typealias AssociatedStub =
            Stub<any ExplicitTypedThrowsAssociatedProbe<Int>>
        let element = AssociatedStub.Requirement.Value.associatedType(
            named: "Element"
        )
        let associated = try AssociatedStub(
            .method(
                returning: element,
                throwing: TypedThrowsRequirementError.self
            )
        )
        associated.when { try $0.load() }.thenReturn(42)
        #expect(try associated().load() == 42)
    }

    @Test func linkedValidationChecksTheTypedError() throws {
        _ = RealTypedThrowsRequirementProbe()
        let matching = try Stub<any TypedThrowsRequirementProbe>(
            .method(
                returning: Int.self,
                throwing: TypedThrowsRequirementError.self
            )
        )
        matching.when { try $0.load() }.thenReturn(42)
        #expect(try matching().load() == 42)

        #expect(throws: StubError.self) {
            _ = try Stub<any TypedThrowsRequirementProbe>(
                .method(
                    returning: Int.self,
                    throwing: OtherTypedThrowsRequirementError.self
                )
            )
        }
    }

    @Test func withValuePreservesTypedErrors() throws {
        let stub = try Stub<any TypedThrowsRequirementProbe>()

        #expect(throws: TypedThrowsRequirementError.failed) {
            try callWithValue(stub)
        }
    }
}
