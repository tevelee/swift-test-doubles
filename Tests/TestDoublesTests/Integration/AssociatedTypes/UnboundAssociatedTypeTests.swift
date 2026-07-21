import Testing
@testable import TestDoubles

protocol CallerBoundSource<Element> {
    associatedtype Element: Equatable
    func next() -> Element
    func load() async throws -> Element
    var current: Element { get }
}

struct LinkedCallerBoundSource: CallerBoundSource {
    func next() -> Int { 0 }
    func load() async throws -> Int { 0 }
    var current: Int { 0 }
}

private protocol ExplicitCallerBoundSource<Element> {
    associatedtype Element
    func next() -> Element
    var current: Element { get }
}

protocol CallerBoundNumericSource<Element> {
    associatedtype Element: BinaryInteger
    func number() -> Element
}

protocol CallerBoundTextSource<Element> {
    associatedtype Element: StringProtocol
    func text() -> Element
}

struct LinkedCallerBoundNumericSource: CallerBoundNumericSource {
    func number() -> Int { 0 }
}

struct LinkedCallerBoundTextSource: CallerBoundTextSource {
    func text() -> String { "" }
}

protocol CallerBoundBaseSource<Element> {
    associatedtype Element
    func baseValue() -> Element
}

protocol CallerBoundDerivedSource: CallerBoundBaseSource {}

struct LinkedCallerBoundDerivedSource: CallerBoundDerivedSource {
    func baseValue() -> Int { 0 }
}

protocol CallerBoundSink<Element> {
    associatedtype Element
    func consume(_ value: Element)
}

struct LinkedCallerBoundSink: CallerBoundSink {
    func consume(_ value: Int) {}
}

struct CallerBoundTypedFailure: Error, Equatable {
    let code: Int
}

protocol CallerBoundTypedThrowingProbe<Failure> {
    associatedtype Failure: Error
    func load(_ shouldFail: Bool) throws(Failure) -> Int
}

struct LinkedCallerBoundTypedThrowingProbe: CallerBoundTypedThrowingProbe {
    func load(_ shouldFail: Bool) throws(CallerBoundTypedFailure) -> Int { 0 }
}

private protocol ForeignCallerBoundSource<Element> {
    associatedtype Element
}

private final class NonEquatableCallerBinding {}

@Suite struct UnboundAssociatedTypeTests {
    @Test func automaticMethodGetterAndAsyncResultUseCallerBinding() async throws {
        _ = LinkedCallerBoundSource()
        typealias SourceStub = Stub<any CallerBoundSource>
        let stub = try SourceStub(
            associatedTypes: [
                .binding(
                    declaredBy: (any CallerBoundSource).self,
                    named: "Element",
                    to: String.self
                )
            ]
        )
        stub.when { $0.next() }.thenReturn("next")
        stub.when { $0.current }.thenReturn("current")
        await stub.when { try await $0.load() }.then {
            () async throws -> any Equatable in "loaded"
        }

        let source = stub()

        #expect(source.next() as? String == "next")
        #expect(source.current as? String == "current")
        #expect(try await source.load() as? String == "loaded")
        #expect(callerBoundElementType(of: source) == ObjectIdentifier(String.self))
    }

    @Test func associatedTypedErrorUsesCallerBinding() throws {
        _ = LinkedCallerBoundTypedThrowingProbe()
        typealias ProbeStub = Stub<any CallerBoundTypedThrowingProbe>
        let stub = try ProbeStub(
            associatedTypes: [
                .binding(
                    declaredBy: (any CallerBoundTypedThrowingProbe).self,
                    named: "Failure",
                    to: CallerBoundTypedFailure.self
                )
            ]
        )
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(method.typedErrorDependency == .associatedType(name: "Failure"))
        #expect(method.typedErrorUsesIndirectResultSlot)
        stub.when { try $0.load(equal(false)) }.thenReturn(42)
        stub.when { try $0.load(equal(true)) }.thenThrow(CallerBoundTypedFailure(code: 7))

        let probe = stub()
        #expect(try probe.load(false) == 42)
        let error = #expect(throws: CallerBoundTypedFailure.self) {
            _ = try probe.load(true)
        }
        #expect(error == CallerBoundTypedFailure(code: 7))
    }

    @Test func flatExplicitRequirementsDoNotNeedALinkedConformer() throws {
        typealias SourceStub = Stub<any ExplicitCallerBoundSource>
        let element = SourceStub.Requirement.Value
            .associatedType(named: "Element")
        let stub = try SourceStub(
            associatedTypes: [
                .binding(
                    declaredBy: (any ExplicitCallerBoundSource).self,
                    named: "Element",
                    to: Int.self
                )
            ],
            .method(returning: element),
            .getter(element)
        )
        stub.when { $0.next() }.thenReturn(41)
        stub.when { $0.current }.thenReturn(42)

        let source = stub()

        #expect(source.next() as? Int == 41)
        #expect(source.current as? Int == 42)
    }

    @Test func compositionScopesEqualNamesByDeclaringProtocol() throws {
        _ = LinkedCallerBoundNumericSource()
        _ = LinkedCallerBoundTextSource()
        typealias Composition = any CallerBoundNumericSource
            & CallerBoundTextSource
        typealias CompositionStub = Stub<Composition>
        let stub = try CompositionStub(
            associatedTypes: [
                .binding(
                    declaredBy: (any CallerBoundNumericSource).self,
                    named: "Element",
                    to: Int.self
                ),
                .binding(
                    declaredBy: (any CallerBoundTextSource).self,
                    named: "Element",
                    to: String.self
                )
            ]
        )
        let number = try #require(stub.recorder.runtimeMethod(for: 0))
        let text = try #require(stub.recorder.runtimeMethod(for: 1))

        #expect(ObjectIdentifier(number.returnType) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(text.returnType) == ObjectIdentifier(String.self))
    }

    @Test func inheritedBindingNamesTheDeclaringBaseProtocol() throws {
        _ = LinkedCallerBoundDerivedSource()
        typealias SourceStub = Stub<any CallerBoundDerivedSource>
        let stub = try SourceStub(
            associatedTypes: [
                .binding(
                    declaredBy: (any CallerBoundBaseSource).self,
                    named: "Element",
                    to: String.self
                )
            ]
        )
        stub.when { $0.baseValue() }.thenReturn("base")

        #expect(stub().baseValue() as? String == "base")
    }

    @Test func missingDuplicateForeignAndUnknownBindingsFailClosed() {
        _ = LinkedCallerBoundSource()
        typealias SourceStub = Stub<any CallerBoundSource>
        let binding = SourceStub.AssociatedTypeBinding.binding(
            declaredBy: (any CallerBoundSource).self,
            named: "Element",
            to: Int.self
        )

        #expect(throws: StubError.self) {
            _ = try SourceStub(associatedTypes: [])
        }
        #expect(throws: StubError.self) {
            _ = try SourceStub(associatedTypes: [binding, binding])
        }
        #expect(throws: StubError.self) {
            _ = try SourceStub(
                associatedTypes: [
                    .binding(
                        declaredBy: (any ForeignCallerBoundSource).self,
                        named: "Element",
                        to: Int.self
                    )
                ]
            )
        }
        #expect(throws: StubError.self) {
            _ = try SourceStub(
                associatedTypes: [
                    .binding(
                        declaredBy: (any CallerBoundSource).self,
                        named: "Missing",
                        to: Int.self
                    )
                ]
            )
        }
    }

    @Test func existingMetadataBindingCannotBeOverridden() {
        _ = LinkedCallerBoundSource()
        #expect(throws: StubError.self) {
            _ = try Stub<any CallerBoundSource<Int>>(
                associatedTypes: [
                    .binding(
                        declaredBy: (any CallerBoundSource).self,
                        named: "Element",
                        to: String.self
                    )
                ]
            )
        }
    }

    @Test func associatedConformanceConstraintIsValidated() {
        _ = LinkedCallerBoundSource()
        #expect(throws: StubError.self) {
            _ = try Stub<any CallerBoundSource>(
                associatedTypes: [
                    .binding(
                        declaredBy: (any CallerBoundSource).self,
                        named: "Element",
                        to: NonEquatableCallerBinding.self
                    )
                ]
            )
        }
    }

    @Test func associatedInputsRemainFailClosed() {
        _ = LinkedCallerBoundSink()
        expectUnsupportedProtocolShape(containing: "covariant result positions") {
            _ = try Stub<any CallerBoundSink>(
                associatedTypes: [
                    .binding(
                        declaredBy: (any CallerBoundSink).self,
                        named: "Element",
                        to: Int.self
                    )
                ]
            )
        }
    }

    @Test func fixedReturnValuesAreCheckedAgainstBoundMetadata() throws {
        _ = LinkedCallerBoundSource()
        let stub = try Stub<any CallerBoundSource>(
            associatedTypes: [
                .binding(
                    declaredBy: (any CallerBoundSource).self,
                    named: "Element",
                    to: Int.self
                )
            ]
        )
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(ObjectIdentifier(method.returnType) == ObjectIdentifier(Int.self))
        #expect(stub.recorder.returnValueMatchesRuntimeType(42, for: 0))
        #expect(stub.recorder.returnValueMatchesRuntimeType("wrong", for: 0) == false)
    }
}

private func callerBoundElementType<P: CallerBoundSource>(
    of _: P
) -> ObjectIdentifier {
    ObjectIdentifier(P.Element.self)
}
