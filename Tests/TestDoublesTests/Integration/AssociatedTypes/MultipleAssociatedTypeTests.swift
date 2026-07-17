import Testing
@testable import TestDoubles

protocol MultipleAssociatedTypeProbe<Number, Text> {
    associatedtype Number: BinaryInteger
    associatedtype Text: StringProtocol
    func number() -> Number
    func text() -> Text
    func render(_ number: Number, as text: Text) -> Text
}

struct LinkedMultipleAssociatedTypeProbe: MultipleAssociatedTypeProbe {
    func number() -> Int { 0 }
    func text() -> String { "" }
    func render(_ number: Int, as text: String) -> String { "\(number):\(text)" }
}

protocol NumericAssociatedRoot<Number> {
    associatedtype Number: BinaryInteger
    func numericValue() -> Number
}

protocol TextAssociatedRoot<Text> {
    associatedtype Text: StringProtocol
    func textValue() -> Text
}

struct LinkedNumericAssociatedRoot: NumericAssociatedRoot {
    func numericValue() -> Int { 0 }
}

struct LinkedTextAssociatedRoot: TextAssociatedRoot {
    func textValue() -> String { "" }
}

protocol PrefixAssociatedTypeProbe<Element, ElementIndex> {
    associatedtype Element
    associatedtype ElementIndex: BinaryInteger
    func element() -> Element
    func index() -> ElementIndex
    func transform(indexes: [ElementIndex]) -> [ElementIndex]
}

struct LinkedPrefixAssociatedTypeProbe: PrefixAssociatedTypeProbe {
    func element() -> String { "" }
    func index() -> Int { 0 }
    func transform(indexes: [Int]) -> [Int] { indexes }
}

protocol InheritedMultipleAssociatedTypeProbe<Number, Text>:
    MultipleAssociatedTypeProbe
{}

@inline(never)
private func useLinkedMultipleAssociatedTypeProbe(
    _ value: any MultipleAssociatedTypeProbe<Int, String>
) -> String {
    value.render(0, as: "")
}

@inline(never)
private func useLinkedNumericAssociatedRoot(
    _ value: any NumericAssociatedRoot<Int>
) -> Int {
    value.numericValue()
}

@inline(never)
private func useLinkedTextAssociatedRoot(
    _ value: any TextAssociatedRoot<String>
) -> String {
    value.textValue()
}

private func constrainedSummary<P: MultipleAssociatedTypeProbe>(
    _ value: P
) -> String {
    "\(value.number() + 1):\(value.text().uppercased())"
}

private func doubledNumericValue<P: NumericAssociatedRoot>(_ value: P) -> P.Number {
    value.numericValue() + value.numericValue()
}

private func uppercasedTextValue<P: TextAssociatedRoot>(_ value: P) -> String {
    value.textValue().uppercased()
}

@Suite struct MultipleAssociatedTypeTests {
    @Test func automaticDiscoveryMapsDistinctBindingsAndConformances() throws {
        #expect(
            useLinkedMultipleAssociatedTypeProbe(
                LinkedMultipleAssociatedTypeProbe()
            ) == "0:"
        )
        let stub = try Stub<any MultipleAssociatedTypeProbe<Int, String>>()
        stub.when { $0.number() }.thenReturn(41)
        stub.when { $0.text() }.thenReturn("bound")
        stub.when { $0.render(any(), as: any()) }.then {
            (number: Int, text: String) in "\(number):\(text)"
        }

        let probe: any MultipleAssociatedTypeProbe<Int, String> = stub()

        #expect(probe.number() == 41)
        #expect(probe.text() == "bound")
        #expect(probe.render(42, as: "value") == "42:value")
        #expect(constrainedSummary(probe) == "42:BOUND")
    }

    @Test func groupedExplicitConstructionNamesEachAssociatedType() throws {
        typealias Probe = any MultipleAssociatedTypeProbe<Int, String>
        typealias ProbeStub = Stub<Probe>
        let number = ProbeStub.Requirement.Value.associatedType(named: "Number")
        let text = ProbeStub.Requirement.Value.associatedType(named: "Text")
        let stub = try ProbeStub(
            requirementsByProtocol: .requirements(
                declaredBy: (any MultipleAssociatedTypeProbe).self,
                .method(returning: number),
                .method(returning: text),
                .method(number, text, returning: text)
            )
        )
        stub.when { $0.number() }.thenReturn(42)
        stub.when { $0.text() }.thenReturn("explicit")
        stub.when { $0.render(any(), as: any()) }.thenReturn("rendered")

        let probe: Probe = stub()

        #expect(probe.number() == 42)
        #expect(probe.text() == "explicit")
        #expect(probe.render(0, as: "") == "rendered")
        #expect(constrainedSummary(probe) == "43:EXPLICIT")
    }

    @Test func twoAssociatedRootsKeepDistinctBindings() throws {
        #expect(useLinkedNumericAssociatedRoot(LinkedNumericAssociatedRoot()) == 0)
        #expect(useLinkedTextAssociatedRoot(LinkedTextAssociatedRoot()) == "")
        typealias CompositionProtocol =
            NumericAssociatedRoot<Int> & TextAssociatedRoot<String>
        typealias Composition = any CompositionProtocol
        let stub = try Stub<Composition>()
        stub.when { $0.numericValue() }.thenReturn(21)
        stub.when { $0.textValue() }.thenReturn("composed")

        let probe: Composition = stub()

        #expect(doubledNumericValue(probe) == 42)
        #expect(uppercasedTextValue(probe) == "COMPOSED")
    }

    @Test func twoAssociatedRootsSupportGroupedExplicitConstruction() throws {
        typealias CompositionProtocol =
            NumericAssociatedRoot<Int> & TextAssociatedRoot<String>
        typealias Composition = any CompositionProtocol
        typealias CompositionStub = Stub<Composition>
        let numeric = CompositionStub.Requirement.Value
            .associatedType(named: "Number")
        let text = CompositionStub.Requirement.Value
            .associatedType(named: "Text")
        let stub = try CompositionStub(
            requirementsByProtocol: .requirements(
                declaredBy: (any TextAssociatedRoot).self,
                .method(returning: text)
            ),
            .requirements(
                declaredBy: (any NumericAssociatedRoot).self,
                .method(returning: numeric)
            )
        )
        stub.when { $0.numericValue() }.thenReturn(42)
        stub.when { $0.textValue() }.thenReturn("explicit composition")

        let probe: Composition = stub()

        #expect(probe.numericValue() == 42)
        #expect(probe.textValue() == "explicit composition")
    }

    @Test func inheritedLayoutPreservesBothBindingIdentities() throws {
        typealias Probe = any InheritedMultipleAssociatedTypeProbe<Int, String>
        typealias ProbeStub = Stub<Probe>
        let number = ProbeStub.Requirement.Value.associatedType(named: "Number")
        let text = ProbeStub.Requirement.Value.associatedType(named: "Text")
        let stub = try ProbeStub(
            requirementsByProtocol: .requirements(
                declaredBy: (any MultipleAssociatedTypeProbe).self,
                .method(returning: number),
                .method(returning: text),
                .method(number, text, returning: text)
            )
        )
        stub.when { $0.number() }.thenReturn(42)
        stub.when { $0.text() }.thenReturn("inherited")
        stub.when { $0.render(any(), as: any()) }.thenReturn("inherited render")

        let probe: Probe = stub()

        #expect(probe.number() == 42)
        #expect(probe.text() == "inherited")
        #expect(probe.render(0, as: "") == "inherited render")
    }

    @Test func prefixAssociatedTypeNamesResolveTheExactBindingFirst() throws {
        _ = LinkedPrefixAssociatedTypeProbe().transform(indexes: [])
        let stub = try Stub<any PrefixAssociatedTypeProbe<String, Int>>()
        stub.when { $0.element() }.thenReturn("element")
        stub.when { $0.index() }.thenReturn(41)
        stub.when { $0.transform(indexes: any()) }.then { (indexes: [Int]) in
            indexes.map { $0 + 1 }
        }

        let probe: any PrefixAssociatedTypeProbe<String, Int> = stub()

        #expect(probe.element() == "element")
        #expect(probe.index() == 41)
        #expect(probe.transform(indexes: [1, 2]) == [2, 3])
    }

    @Test func swappedOrUnknownExplicitBindingsFailClosed() {
        typealias Probe = any MultipleAssociatedTypeProbe<Int, String>
        typealias ProbeStub = Stub<Probe>
        let number = ProbeStub.Requirement.Value.associatedType(named: "Number")
        let text = ProbeStub.Requirement.Value.associatedType(named: "Text")
        let missing = ProbeStub.Requirement.Value.associatedType(named: "Missing")

        #expect(throws: StubError.self) {
            _ = try ProbeStub(
                requirementsByProtocol: .requirements(
                    declaredBy: (any MultipleAssociatedTypeProbe).self,
                    .method(returning: text),
                    .method(returning: number),
                    .method(number, text, returning: text)
                )
            )
        }
        #expect(throws: StubError.self) {
            _ = try ProbeStub(
                requirementsByProtocol: .requirements(
                    declaredBy: (any MultipleAssociatedTypeProbe).self,
                    .method(returning: missing),
                    .method(returning: text),
                    .method(number, text, returning: text)
                )
            )
        }
    }
}
