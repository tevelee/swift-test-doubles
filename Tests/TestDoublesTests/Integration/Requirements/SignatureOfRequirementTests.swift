import Testing
@testable import TestDoubles

enum SignatureOfRequirementError: Error, Equatable {
    case rejected(Int)
}

protocol SignatureOfMethodProbe: Sendable {
    func render(_ value: Int, label: String) -> String
    func zero() -> Bool
    func untyped(_ value: Int) throws -> String
    func typed(_ value: Int) throws(SignatureOfRequirementError) -> String
    func asynchronous(_ value: Int) async -> String
    func asynchronousTyped(_ value: Int) async throws(SignatureOfRequirementError) -> String
    func six(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int) -> Int
}

protocol SignatureOfPropertyProbe: Sendable {
    var count: Int { get set }
    var title: String { get }
    var throwingValue: Int { get throws }
    var asynchronousValue: Int { get async }
    var asynchronousThrowingValue: Int { get async throws }
}

protocol SignatureOfAssociatedProbe<Element> {
    associatedtype Element
    func load() -> Element
}

protocol SignatureOfSelfProbe {
    func duplicate() -> Self
}

protocol SignatureOfTypedGetterProbe {
    var value: Int { get throws(SignatureOfRequirementError) }
}

protocol SignatureOfArityProbe {
    func synchronous0() -> Int
    func throwing0() throws -> Int
    func asynchronous0() async -> Int
    func asynchronousThrowing0() async throws -> Int
    func synchronous1(_ a0: Int) -> Int
    func throwing1(_ a0: Int) throws -> Int
    func asynchronous1(_ a0: Int) async -> Int
    func asynchronousThrowing1(_ a0: Int) async throws -> Int
    func synchronous2(_ a0: Int, _ a1: Int) -> Int
    func throwing2(_ a0: Int, _ a1: Int) throws -> Int
    func asynchronous2(_ a0: Int, _ a1: Int) async -> Int
    func asynchronousThrowing2(_ a0: Int, _ a1: Int) async throws -> Int
    func synchronous3(_ a0: Int, _ a1: Int, _ a2: Int) -> Int
    func throwing3(_ a0: Int, _ a1: Int, _ a2: Int) throws -> Int
    func asynchronous3(_ a0: Int, _ a1: Int, _ a2: Int) async -> Int
    func asynchronousThrowing3(_ a0: Int, _ a1: Int, _ a2: Int) async throws -> Int
    func synchronous4(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int) -> Int
    func throwing4(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int) throws -> Int
    func asynchronous4(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int) async -> Int
    func asynchronousThrowing4(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int) async throws -> Int
    func synchronous5(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int) -> Int
    func throwing5(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int) throws -> Int
    func asynchronous5(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int) async -> Int
    func asynchronousThrowing5(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int
    ) async throws -> Int
    func synchronous6(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
    ) -> Int
    func throwing6(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
    ) throws -> Int
    func asynchronous6(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
    ) async -> Int
    func asynchronousThrowing6(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
    ) async throws -> Int
}

struct SignatureOfRequirementTests {
    @Test func methodReferenceOverloadsCoverEverySupportedFixedArity() {
        typealias Requirement = Stub<any SignatureOfArityProbe>.Requirement

        let requirements: [Requirement] = [
            .method(signatureOf: SignatureOfArityProbe.synchronous0),
            .method(signatureOf: SignatureOfArityProbe.throwing0),
            .method(signatureOf: SignatureOfArityProbe.asynchronous0),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing0),
            .method(signatureOf: SignatureOfArityProbe.synchronous1),
            .method(signatureOf: SignatureOfArityProbe.throwing1),
            .method(signatureOf: SignatureOfArityProbe.asynchronous1),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing1),
            .method(signatureOf: SignatureOfArityProbe.synchronous2),
            .method(signatureOf: SignatureOfArityProbe.throwing2),
            .method(signatureOf: SignatureOfArityProbe.asynchronous2),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing2),
            .method(signatureOf: SignatureOfArityProbe.synchronous3),
            .method(signatureOf: SignatureOfArityProbe.throwing3),
            .method(signatureOf: SignatureOfArityProbe.asynchronous3),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing3),
            .method(signatureOf: SignatureOfArityProbe.synchronous4),
            .method(signatureOf: SignatureOfArityProbe.throwing4),
            .method(signatureOf: SignatureOfArityProbe.asynchronous4),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing4),
            .method(signatureOf: SignatureOfArityProbe.synchronous5),
            .method(signatureOf: SignatureOfArityProbe.throwing5),
            .method(signatureOf: SignatureOfArityProbe.asynchronous5),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing5),
            .method(signatureOf: SignatureOfArityProbe.synchronous6),
            .method(signatureOf: SignatureOfArityProbe.throwing6),
            .method(signatureOf: SignatureOfArityProbe.asynchronous6),
            .method(signatureOf: SignatureOfArityProbe.asynchronousThrowing6)
        ]

        for (index, requirement) in requirements.enumerated() {
            #expect(requirement.arguments.count == index / 4)
            #expect(requirement.isThrowing == (index % 4 == 1 || index % 4 == 3))
            #expect(requirement.isAsync == (index % 4 >= 2))
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func methodReferencesInferConcreteTypesAndEffects() async throws {
        let stub = try Stub<any SignatureOfMethodProbe>(
            .method(signatureOf: SignatureOfMethodProbe.render),
            .method(signatureOf: SignatureOfMethodProbe.zero),
            .method(signatureOf: SignatureOfMethodProbe.untyped),
            .method(signatureOf: SignatureOfMethodProbe.typed),
            .method(signatureOf: SignatureOfMethodProbe.asynchronous),
            .method(signatureOf: SignatureOfMethodProbe.asynchronousTyped),
            .method(signatureOf: SignatureOfMethodProbe.six)
        )

        let methods = try (0 ..< 7).map {
            try #require(stub.recorder.runtimeMethod(for: $0))
        }
        #expect(methods[0].argumentTypes.count == 2)
        #expect(ObjectIdentifier(methods[0].argumentTypes[0]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(methods[0].argumentTypes[1]) == ObjectIdentifier(String.self))
        #expect(ObjectIdentifier(methods[0].returnType) == ObjectIdentifier(String.self))
        #expect(methods[0].isThrowing == false)
        #expect(methods[0].isAsync == false)
        #expect(methods[1].argumentTypes.isEmpty)
        #expect(ObjectIdentifier(methods[1].returnType) == ObjectIdentifier(Bool.self))
        #expect(methods[2].isThrowing)
        #expect(methods[2].typedErrorType == nil)
        #expect(methods[3].isThrowing)
        #expect(
            methods[3].typedErrorType.map(ObjectIdentifier.init)
                == ObjectIdentifier(SignatureOfRequirementError.self)
        )
        #expect(methods[4].isAsync)
        #expect(methods[4].isThrowing == false)
        #expect(methods[5].isAsync)
        #expect(methods[5].isThrowing)
        #expect(
            methods[5].typedErrorType.map(ObjectIdentifier.init)
                == ObjectIdentifier(SignatureOfRequirementError.self)
        )
        #expect(methods[6].argumentTypes.count == 6)
        #expect(ObjectIdentifier(methods[6].returnType) == ObjectIdentifier(Int.self))

        stub.when { $0.render(any(), label: any()) }.thenReturn("rendered")
        await stub.when { try await $0.asynchronousTyped(any()) }.thenReturn("loaded")

        let probe: any SignatureOfMethodProbe = stub()
        #expect(probe.render(7, label: "value") == "rendered")
        #expect(try await probe.asynchronousTyped(4) == "loaded")
    }

    @Test func propertyReferencesInferValueTypesAndGetterEffects() async throws {
        let stub = try Stub<any SignatureOfPropertyProbe>(
            .getter(signatureOf: \SignatureOfPropertyProbe.count),
            .setter(signatureOf: \SignatureOfPropertyProbe.count),
            .getter(signatureOf: \SignatureOfPropertyProbe.title),
            .getter(signatureOf: { try $0.throwingValue }),
            .getter(signatureOf: { await $0.asynchronousValue }),
            .getter(signatureOf: { try await $0.asynchronousThrowingValue })
        )

        let methods = try (0 ..< 6).map {
            try #require(stub.recorder.runtimeMethod(for: $0))
        }
        #expect(ObjectIdentifier(methods[0].returnType) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(methods[1].argumentTypes[0]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(methods[2].returnType) == ObjectIdentifier(String.self))
        #expect(methods[3].isThrowing)
        #expect(methods[3].isAsync == false)
        #expect(methods[4].isThrowing == false)
        #expect(methods[4].isAsync)
        #expect(methods[5].isThrowing)
        #expect(methods[5].isAsync)

        stub.when { $0.count }.thenReturn(7)
        stub.when { $0.count = any() }.thenDoNothing()
        stub.when { $0.title }.thenReturn("title")
        stub.when { try $0.throwingValue }.thenReturn(8)
        await stub.when { await $0.asynchronousValue }.thenReturn(9)
        await stub.when { try await $0.asynchronousThrowingValue }.thenReturn(10)

        var probe: any SignatureOfPropertyProbe = stub()
        #expect(probe.count == 7)
        probe.count = 11
        #expect(probe.title == "title")
        #expect(try probe.throwingValue == 8)
        #expect(await probe.asynchronousValue == 9)
        #expect(try await probe.asynchronousThrowingValue == 10)
        stub.verify { $0.count = equal(11) }
    }

    @Test func associatedTypeSignaturesFailClosedAfterFunctionConversion() {
        typealias AssociatedStub = Stub<any SignatureOfAssociatedProbe<Int>>

        expectStubError({
            _ = try AssociatedStub(
                .method(signatureOf: (any SignatureOfAssociatedProbe<Int>).load)
            )
        }) { error in
            guard case .unsupportedProtocolShape(_, let reason) = error else { return false }
            return reason.contains("Function conversion erases associated-type identity")
        }
    }

    @Test func dynamicSelfSignaturesFailClosedAfterFunctionConversion() {
        expectStubError({
            _ = try Stub<any SignatureOfSelfProbe>(
                .method(signatureOf: (any SignatureOfSelfProbe).duplicate)
            )
        }) { error in
            guard case .unsupportedProtocolShape(_, let reason) = error else { return false }
            return reason.contains("may represent dynamic `Self`")
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func typedThrowingGetterSignaturesRemainUnsupported() {
        let getter:
            (any SignatureOfTypedGetterProbe)
                throws(SignatureOfRequirementError) -> Int = { try $0.value }

        expectStubError({
            _ = try Stub<any SignatureOfTypedGetterProbe>(
                .getter(signatureOf: getter)
            )
        }) { error in
            guard case .unsupportedProtocolShape(_, let reason) = error else { return false }
            return reason.contains("Typed-throwing accessors are unsupported")
        }
    }
}
