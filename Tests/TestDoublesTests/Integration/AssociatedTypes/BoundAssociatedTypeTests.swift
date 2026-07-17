import Foundation
import Testing
@testable import TestDoubles

protocol BoundAssociatedTypeProbe<Element> {
    associatedtype Element: Equatable
    func value() -> Element
    func transform(_ value: Element) -> Element
    func mix(_ fixed: Int, _ value: Element) -> Element
    var current: Element { get }
}
struct RealBoundAssociatedTypeProbe: BoundAssociatedTypeProbe {
    func value() -> Int { 1 }
    func transform(_ value: Int) -> Int { value }
    func mix(_ fixed: Int, _ value: Int) -> Int { fixed + value }
    var current: Int { 1 }
}
private protocol ExplicitOnlyBoundAssociatedTypeProbe<Element> {
    associatedtype Element: Equatable
    func value() -> Element
}
private protocol NestedBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func wrapped(_ value: Element?) -> Element?
}
private struct RealNestedBoundAssociatedTypeProbe: NestedBoundAssociatedTypeProbe {
    func wrapped(_ value: Int?) -> Int? { value }
}
// Runtime-discovery fixtures must remain module-internal so optimized tests
// continue to dispatch through their linked and fabricated witness tables.
protocol ConsumingBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func consume(_ value: consuming Element)
    func consumeAsync(_ value: consuming Element) async
}
final class BoundAssociatedTypeBox: @unchecked Sendable {
    private let deinitCounter: LockedCounter?

    init(deinitCounter: LockedCounter? = nil) {
        self.deinitCounter = deinitCounter
    }

    deinit {
        deinitCounter?.increment()
    }
}
protocol ReferenceElementAssociatedTypeProbe<Element> {
    associatedtype Element: AnyObject
    func transform(_ value: Element) -> Element
}
struct RealReferenceElementAssociatedTypeProbe:
    ReferenceElementAssociatedTypeProbe
{
    func transform(_ value: BoundAssociatedTypeBox) -> BoundAssociatedTypeBox {
        value
    }
}
struct RealConsumingBoundAssociatedTypeProbe: ConsumingBoundAssociatedTypeProbe {
    func consume(_ value: consuming BoundAssociatedTypeBox) {}
    func consumeAsync(_ value: consuming BoundAssociatedTypeBox) async {}
}

enum BoundAssociatedTypeRequirementSource: CaseIterable, Sendable {
    case automatic
    case explicit
}
protocol EffectfulBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func load() async throws -> Element
    func advance(_ value: Element) async -> Element
}
struct RealEffectfulBoundAssociatedTypeProbe: EffectfulBoundAssociatedTypeProbe {
    func load() async throws -> Int { 1 }
    func advance(_ value: Int) async -> Int { value }
}
private protocol ExplicitEffectfulBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func load() async throws -> Element
    var current: Element { get async throws }
}
protocol ThrowingBoundAssociatedTypeProbe<Element> {
    associatedtype Element: Equatable
    func load() throws -> Element
    func transform(_ value: Element) throws -> Element
}
struct RealThrowingBoundAssociatedTypeProbe: ThrowingBoundAssociatedTypeProbe {
    func load() throws -> Int { 1 }
    func transform(_ value: Int) throws -> Int { value }
}
struct ThrowingProbeError: Error, Equatable {
    let value: Int
}
private protocol ExplicitThrowingBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func load() throws -> Element
    var current: Element { get throws }
}
protocol TypedThrowingBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func load() throws(ThrowingProbeError) -> Element
}
struct RealTypedThrowingBoundAssociatedTypeProbe:
    TypedThrowingBoundAssociatedTypeProbe
{
    func load() throws(ThrowingProbeError) -> Int { 1 }
}
protocol TypedThrowingArrayBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func load() throws(ThrowingProbeError) -> [Element]
}
struct RealTypedThrowingArrayBoundAssociatedTypeProbe:
    TypedThrowingArrayBoundAssociatedTypeProbe
{
    func load() throws(ThrowingProbeError) -> [Int] { [1] }
}
private protocol MultipleBoundAssociatedTypeProbe<First, Second> {
    associatedtype First
    associatedtype Second
}
protocol BoundAssociatedTypeSetterProbe<Element> {
    associatedtype Element
    var value: Element { get set }
}
struct RealBoundAssociatedTypeSetterProbe: BoundAssociatedTypeSetterProbe {
    var value: Int
}
protocol BoundAssociatedTypeBaseProbe<Element> {
    associatedtype Element
    func base(_ value: Element) -> Element
}
protocol InheritedBoundAssociatedTypeProbe<Element>:
    BoundAssociatedTypeBaseProbe
{}
struct RealInheritedBoundAssociatedTypeProbe:
    InheritedBoundAssociatedTypeProbe
{
    func base(_ value: Int) -> Int { value }
}
protocol MixedDeclarationBoundAssociatedTypeBaseProbe {
    func label() -> String
}
protocol MixedDeclarationBoundAssociatedTypeProbe<Element>:
    MixedDeclarationBoundAssociatedTypeBaseProbe
{
    associatedtype Element: Equatable
    func value() -> Element
    func transform(_ value: Element) -> Element
}
struct RealMixedDeclarationBoundAssociatedTypeProbe:
    MixedDeclarationBoundAssociatedTypeProbe
{
    func label() -> String { "mixed" }
    func value() -> Int { 1 }
    func transform(_ value: Int) -> Int { value }
}
protocol AssociatedCompositionProbe {
    func label() -> String
}
struct RealAssociatedCompositionProbe: AssociatedCompositionProbe {
    func label() -> String { "linked" }
}
protocol ClassAssociatedTypeProbe<Element>: AnyObject, Sendable {
    associatedtype Element: Equatable
    func value() -> Element
    func transform(_ value: Element) -> Element
}
final class RealClassAssociatedTypeProbe:
    ClassAssociatedTypeProbe, @unchecked Sendable
{
    func value() -> Int { 0 }
    func transform(_ value: Int) -> Int { value }
}
private protocol ExplicitClassAssociatedTypeProbe<Element>: AnyObject {
    associatedtype Element
    func value() -> Element
}
private protocol SuperclassBoundAssociatedTypeProbe<Element> {
    associatedtype Element
    func value() -> Element
}
private final class RealSuperclassBoundAssociatedTypeProbe:
    NSObject, SuperclassBoundAssociatedTypeProbe
{
    func value() -> Int { 0 }
}
protocol ClassAssociatedCompositionProbe: AnyObject {
    func label() -> String
}
final class RealClassAssociatedCompositionProbe:
    ClassAssociatedCompositionProbe
{
    func label() -> String { "linked" }
}
private func valuesAreEqual<P: BoundAssociatedTypeProbe>(_ value: P) -> Bool {
    value.value() == value.current
}

@inline(never)
private func useLinkedAssociatedTypeProbe(
    _ value: any BoundAssociatedTypeProbe<Int>
) -> Int {
    value.transform(0)
}

@inline(never)
private func useLinkedEffectfulAssociatedTypeProbe(
    _ value: any EffectfulBoundAssociatedTypeProbe<Int>
) async -> Int {
    await value.advance(0)
}

@inline(never)
private func useLinkedThrowingAssociatedTypeProbe(
    _ value: any ThrowingBoundAssociatedTypeProbe<Int>
) throws -> Int {
    try value.transform(0)
}

@inline(never)
private func useLinkedAssociatedCompositionProbe(
    _ value: any AssociatedCompositionProbe
) -> String {
    value.label()
}

@inline(never)
private func useLinkedMixedDeclarationAssociatedTypeProbe(
    _ value: any MixedDeclarationBoundAssociatedTypeProbe<Int>
) -> Int {
    value.transform(0)
}

@inline(never)
private func useLinkedClassAssociatedTypeProbe(
    _ value: any ClassAssociatedTypeProbe<Int>
) -> Int {
    value.transform(0)
}

@inline(never)
private func useLinkedClassAssociatedCompositionProbe(
    _ value: any ClassAssociatedCompositionProbe
) -> String {
    value.label()
}

@inline(never)
private func useLinkedBoundAssociatedTypeSetterProbe(
    _ value: any BoundAssociatedTypeSetterProbe<Int>
) -> Int {
    value.value
}

@inline(never)
private func useLinkedConsumingBoundAssociatedTypeProbe(
    _ value: any ConsumingBoundAssociatedTypeProbe<BoundAssociatedTypeBox>
) {
    value.consume(BoundAssociatedTypeBox())
}

private func inheritedValue<P: InheritedBoundAssociatedTypeProbe>(
    _ value: P,
    input: P.Element
) -> P.Element {
    value.base(input)
}

@Suite struct BoundAssociatedTypeTests {
    @Test func automaticDiscoveryUsesDependentCallingConventions() throws {
        #expect(useLinkedAssociatedTypeProbe(RealBoundAssociatedTypeProbe()) == 0)
        let stub = try Stub<any BoundAssociatedTypeProbe<Int>>()
        let value = try #require(stub.recorder.runtimeMethod(for: 0))
        let transform = try #require(stub.recorder.runtimeMethod(for: 1))
        let mix = try #require(stub.recorder.runtimeMethod(for: 2))
        #expect(value.returnConvention == .associatedType(name: "Element"))
        #expect(transform.argumentConventions == [.associatedType(name: "Element")])
        #expect(mix.argumentConventions == [.concrete, .associatedType(name: "Element")])
        stub.when { $0.value() }.thenReturn(41)
        stub.when { $0.transform(any()) }.then { (value: Int) in value + 1 }
        stub.when { $0.mix(any(), any()) }.then { (fixed: Int, value: Int) in fixed * value }
        stub.when { $0.current }.thenReturn(41)
        let probe: any BoundAssociatedTypeProbe<Int> = stub()
        #expect(probe.value() == 41)
        #expect(probe.transform(41) == 42)
        #expect(probe.mix(6, 7) == 42)
        let genericEquality = valuesAreEqual(probe)
        #expect(genericEquality)
    }

    @Test func explicitRequirementsCanNameTheAssociatedType() throws {
        #expect(useLinkedAssociatedTypeProbe(RealBoundAssociatedTypeProbe()) == 0)
        let associated = Stub<any BoundAssociatedTypeProbe<Int>>.Requirement.Value
            .associatedType(named: "Element")
        let concrete = Stub<any BoundAssociatedTypeProbe<Int>>.Requirement.Value
            .concrete(Int.self)
        let stub = try Stub<any BoundAssociatedTypeProbe<Int>>(
            .method(returning: associated),
            .method(associated, returning: associated),
            .method(concrete, associated, returning: associated),
            .getter(associated)
        )
        stub.when { $0.value() }.thenReturn(7)
        stub.when { $0.transform(any()) }.thenReturn(8)
        stub.when { $0.mix(any(), any()) }.thenReturn(9)
        stub.when { $0.current }.thenReturn(10)
        #expect(stub().value() == 7)
        #expect(stub().transform(0) == 8)
        #expect(stub().mix(0, 0) == 9)
        #expect(stub().current == 10)
    }

    @Test func explicitRequirementsDoNotNeedALinkedConformer() throws {
        typealias ExplicitStub = Stub<any ExplicitOnlyBoundAssociatedTypeProbe<Int>>
        let associated = ExplicitStub.Requirement.Value
            .associatedType(named: "Element")
        let stub = try ExplicitStub(.method(returning: associated))
        stub.when { $0.value() }.thenReturn(42)
        #expect(stub().value() == 42)
    }

    @Test(arguments: BoundAssociatedTypeRequirementSource.allCases)
    func dependentGetterAndSetterPreserveOwnedStorage(
        source: BoundAssociatedTypeRequirementSource
    ) throws {
        #expect(useLinkedBoundAssociatedTypeSetterProbe(RealBoundAssociatedTypeSetterProbe(value: 0)) == 0)
        let (weakReference, deinitCounter) = try exerciseDependentSetter(source: source)

        #expect(weakReference.value == nil)
        #expect(deinitCounter.value == 1)
    }

    @Test(arguments: BoundAssociatedTypeRequirementSource.allCases)
    func consumingDependentArgumentsPreserveOwnedStorage(
        source: BoundAssociatedTypeRequirementSource
    ) async throws {
        useLinkedConsumingBoundAssociatedTypeProbe(RealConsumingBoundAssociatedTypeProbe())
        let lifetimes = try await exerciseConsumingDependentArguments(source: source)

        #expect(lifetimes.sync.value == nil)
        #expect(lifetimes.async.value == nil)
        #expect(lifetimes.syncCounter.value == 1)
        #expect(lifetimes.asyncCounter.value == 1)
    }

    @Test func substitutedConcreteTypeDoesNotSelectTheConcreteABI() {
        #expect(useLinkedAssociatedTypeProbe(RealBoundAssociatedTypeProbe()) == 0)
        typealias IntStub = Stub<any BoundAssociatedTypeProbe<Int>>
        let concrete = IntStub.Requirement.Value.concrete(Int.self)
        let associated = IntStub.Requirement.Value.associatedType(named: "Element")
        #expect(throws: StubError.self) {
            _ = try IntStub(
                .method(returning: concrete),
                .method(associated, returning: associated),
                .method(concrete, associated, returning: associated),
                .getter(associated)
            )
        }
    }

    @Test func bindingNeedNotMatchTheDiscoveryConformer() throws {
        #expect(useLinkedAssociatedTypeProbe(RealBoundAssociatedTypeProbe()) == 0)
        let stub = try Stub<any BoundAssociatedTypeProbe<String>>()
        stub.when { $0.value() }.thenReturn("bound")
        stub.when { $0.transform(any()) }.then { (value: String) in value.uppercased() }
        stub.when { $0.mix(any(), any()) }.thenReturn("mixed")
        stub.when { $0.current }.thenReturn("bound")
        let probe = stub()
        #expect(probe.transform("value") == "VALUE")
        let genericEquality = valuesAreEqual(probe)
        #expect(genericEquality)
    }

    @Test func inheritedProtocolOwnsTheBoundAssociatedTypeWitness() throws {
        #expect(RealInheritedBoundAssociatedTypeProbe().base(0) == 0)
        let stub = try Stub<any InheritedBoundAssociatedTypeProbe<Int>>()
        stub.when { $0.base(any()) }.then { (value: Int) in value + 1 }

        let probe: any InheritedBoundAssociatedTypeProbe<Int> = stub()

        #expect(probe.base(41) == 42)
        #expect(inheritedValue(probe, input: 41) == 42)
    }

    @Test func directlyDeclaredAssociatedTypeCanShareADescriptorWithInheritance() throws {
        #expect(
            useLinkedMixedDeclarationAssociatedTypeProbe(
                RealMixedDeclarationBoundAssociatedTypeProbe()
            ) == 0
        )
        let stub = try Stub<any MixedDeclarationBoundAssociatedTypeProbe<Int>>()
        stub.when { $0.value() }.thenReturn(41)
        stub.when { $0.transform(any()) }.then { (value: Int) in value + 1 }
        stub.when { $0.label() }.thenReturn("stubbed")

        let probe: any MixedDeclarationBoundAssociatedTypeProbe<Int> = stub()

        #expect(probe.value() == 41)
        #expect(probe.transform(41) == 42)
        #expect(probe.label() == "stubbed")
    }

    @Test func associatedTypeCompositionsSupportAutomaticDiscovery() throws {
        #expect(useLinkedAssociatedTypeProbe(RealBoundAssociatedTypeProbe()) == 0)
        #expect(
            useLinkedAssociatedCompositionProbe(RealAssociatedCompositionProbe()) == "linked"
        )
        // `any P<T> & Q` inline trips a Swift 6.1 parser limitation with
        // constrained-existential compositions; composing the protocols in
        // their own typealias first and erasing that works around it.
        typealias CompositionProtocol = BoundAssociatedTypeProbe<Int> & AssociatedCompositionProbe
        typealias Composition = any CompositionProtocol
        let stub = try Stub<Composition>()
        stub.when { $0.value() }.thenReturn(21)
        stub.when { $0.transform(any()) }.then { (value: Int) in value * 2 }
        stub.when { $0.mix(any(), any()) }.then { (fixed: Int, value: Int) in
            fixed + value
        }
        stub.when { $0.current }.thenReturn(21)
        stub.when { $0.label() }.thenReturn("composed")

        let probe: Composition = stub()

        #expect(MemoryLayout<Composition>.size == 6 * MemoryLayout<UInt>.size)
        #expect(probe.transform(21) == 42)
        #expect(probe.mix(20, 22) == 42)
        #expect(probe.label() == "composed")
    }

    @Test func associatedTypeCompositionsSupportGroupedExplicitRequirements() throws {
        typealias CompositionProtocol = BoundAssociatedTypeProbe<Int> & AssociatedCompositionProbe
        typealias Composition = any CompositionProtocol
        typealias CompositionStub = Stub<Composition>
        let element = CompositionStub.Requirement.Value
            .associatedType(named: "Element")
        let concreteInt = CompositionStub.Requirement.Value.concrete(Int.self)
        let stub = try CompositionStub(
            requirementsByProtocol: .requirements(
                declaredBy: AssociatedCompositionProbe.self,
                .method(returning: String.self)
            ),
            .requirements(
                declaredBy: (any BoundAssociatedTypeProbe).self,
                .method(returning: element),
                .method(element, returning: element),
                .method(concreteInt, element, returning: element),
                .getter(element)
            )
        )
        stub.when { $0.value() }.thenReturn(42)
        stub.when { $0.transform(any()) }.thenReturn(42)
        stub.when { $0.mix(any(), any()) }.thenReturn(42)
        stub.when { $0.current }.thenReturn(42)
        stub.when { $0.label() }.thenReturn("explicit")

        let probe: Composition = stub()

        #expect(probe.value() == 42)
        #expect(probe.transform(0) == 42)
        #expect(probe.mix(0, 0) == 42)
        #expect(probe.current == 42)
        #expect(probe.label() == "explicit")
    }

    @Test func classConstrainedAssociatedTypeUsesReferenceExistentialStorage() async throws {
        #expect(
            useLinkedClassAssociatedTypeProbe(RealClassAssociatedTypeProbe()) == 0
        )
        typealias Probe = any ClassAssociatedTypeProbe<Int>
        let stub = try Stub<Probe>()
        stub.when { $0.value() }.thenReturn(42)
        stub.when { $0.transform(any()) }.then { (value: Int) in value }

        let probe: Probe = stub(sendability: .unchecked)

        #expect(MemoryLayout<Probe>.size == 2 * MemoryLayout<UInt>.size)
        #expect(probe.value() == 42)
        #expect(probe.transform(42) == 42)
        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for value in 0 ..< 20 {
                group.addTask {
                    probe.transform(value)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.sorted() == Array(0 ..< 20))
    }

    @Test func explicitClassAssociatedTypeDoesNotNeedALinkedConformer() throws {
        typealias ProbeStub = Stub<any ExplicitClassAssociatedTypeProbe<Int>>
        let element = ProbeStub.Requirement.Value
            .associatedType(named: "Element")
        let stub = try ProbeStub(.method(returning: element))
        stub.when { $0.value() }.thenReturn(42)

        #expect(stub().value() == 42)
    }

    @Test func associatedTypeClassLayoutFailsClosed() {
        _ = RealReferenceElementAssociatedTypeProbe()

        expectUnsupportedProtocolShape(
            containing: "AnyObject-constrained associated types use a dependent reference ABI"
        ) {
            _ = try Stub<any ReferenceElementAssociatedTypeProbe>(
                associatedTypes: [
                    .binding(
                        declaredBy: (any ReferenceElementAssociatedTypeProbe).self,
                        named: "Element",
                        to: BoundAssociatedTypeBox.self
                    )
                ]
            )
        }
    }

    @Test func superclassConstrainedAssociatedTypeFailsClosed() {
        typealias Probe = any NSObject & SuperclassBoundAssociatedTypeProbe<Int>
        _ = RealSuperclassBoundAssociatedTypeProbe()

        expectUnsupportedProtocolShape(
            containing: "Superclass-constrained bound associated-type existentials"
        ) {
            _ = try Stub<Probe>()
        }
    }

    @Test func classAssociatedTypeCompositionCarriesEveryRootWitness() throws {
        #expect(
            useLinkedClassAssociatedTypeProbe(RealClassAssociatedTypeProbe()) == 0
        )
        #expect(
            useLinkedClassAssociatedCompositionProbe(
                RealClassAssociatedCompositionProbe()
            ) == "linked"
        )
        typealias CompositionProtocol = ClassAssociatedTypeProbe<Int> & ClassAssociatedCompositionProbe
        typealias Composition = any CompositionProtocol
        let stub = try Stub<Composition>()
        stub.when { $0.value() }.thenReturn(42)
        stub.when { $0.transform(any()) }.then { (value: Int) in value + 1 }
        stub.when { $0.label() }.thenReturn("class-composed")

        let probe: Composition = stub(sendability: .unchecked)

        #expect(MemoryLayout<Composition>.size == 3 * MemoryLayout<UInt>.size)
        #expect(probe.value() == 42)
        #expect(probe.transform(41) == 42)
        #expect(probe.label() == "class-composed")
    }

    @Test func throwingDependentRequirementsPropagateResultsAndErrors() throws {
        #expect(
            try useLinkedThrowingAssociatedTypeProbe(
                RealThrowingBoundAssociatedTypeProbe()
            ) == 0
        )
        let stub = try Stub<any ThrowingBoundAssociatedTypeProbe<Int>>()
        let load = try #require(stub.recorder.runtimeMethod(for: 0))
        let transform = try #require(stub.recorder.runtimeMethod(for: 1))
        #expect(load.returnConvention == .associatedType(name: "Element"))
        #expect(load.isThrowing)
        #expect(transform.argumentConventions == [.associatedType(name: "Element")])
        #expect(transform.isThrowing)

        stub.when { try $0.load() }.thenReturn(41)
        stub.when { try $0.transform(any()) }.then { (value: Int) throws -> Int in
            if value < 0 { throw ThrowingProbeError(value: value) }
            return value + 1
        }

        let probe: any ThrowingBoundAssociatedTypeProbe<Int> = stub()
        #expect(try probe.load() == 41)
        #expect(try probe.transform(41) == 42)
        let error = #expect(throws: ThrowingProbeError.self) {
            try probe.transform(-1)
        }
        #expect(error?.value == -1)
        stub.verify(.exactly(2)) { try $0.transform(any()) }
    }

    @Test func throwingDependentBindingNeedNotMatchTheDiscoveryConformer() throws {
        #expect(
            try useLinkedThrowingAssociatedTypeProbe(
                RealThrowingBoundAssociatedTypeProbe()
            ) == 0
        )
        let stub = try Stub<any ThrowingBoundAssociatedTypeProbe<String>>()
        stub.when { try $0.load() }.thenReturn("bound")
        stub.when { try $0.transform(any()) }.then { (value: String) throws -> String in
            if value.isEmpty { throw ThrowingProbeError(value: 0) }
            return value.uppercased()
        }

        let probe = stub()

        #expect(try probe.load() == "bound")
        #expect(try probe.transform("value") == "VALUE")
        #expect(throws: ThrowingProbeError.self) { _ = try probe.transform("") }
    }

    @Test func explicitThrowingDependentRequirementsDoNotNeedAConformer() throws {
        typealias ProbeStub = Stub<any ExplicitThrowingBoundAssociatedTypeProbe<Int>>
        let element = ProbeStub.Requirement.Value.associatedType(named: "Element")
        let stub = try ProbeStub(
            .method(returning: element, isThrowing: true),
            .getter(element, isThrowing: true)
        )
        stub.when { try $0.load() }.thenReturn(41)
        stub.when { try $0.current }.thenReturn(42)

        #expect(try stub().load() == 41)
        #expect(try stub().current == 42)
    }

    @Test func asyncDependentRequirementsSuspendAndPropagateResults() async throws {
        #expect(
            await useLinkedEffectfulAssociatedTypeProbe(
                RealEffectfulBoundAssociatedTypeProbe()
            ) == 0
        )
        let stub = try Stub<any EffectfulBoundAssociatedTypeProbe<Int>>()
        let load = try #require(stub.recorder.runtimeMethod(for: 0))
        let advance = try #require(stub.recorder.runtimeMethod(for: 1))
        #expect(load.returnConvention == .associatedType(name: "Element"))
        #expect(load.isAsync)
        #expect(load.isThrowing)
        #expect(advance.argumentConventions == [.associatedType(name: "Element")])
        #expect(advance.isAsync)
        #expect(advance.isThrowing == false)

        await stub.when { try await $0.load() }.thenReturn(41)
        await stub.when { await $0.advance(any()) }.then { (value: Int) async throws -> Int in
            await Task.yield()
            return value + 1
        }

        let probe: any EffectfulBoundAssociatedTypeProbe<Int> = stub()
        #expect(try await probe.load() == 41)
        #expect(await probe.advance(41) == 42)
    }

    @Test func asyncDependentRequirementsPropagateThrownErrors() async throws {
        #expect(
            await useLinkedEffectfulAssociatedTypeProbe(
                RealEffectfulBoundAssociatedTypeProbe()
            ) == 0
        )
        let stub = try Stub<any EffectfulBoundAssociatedTypeProbe<String>>()
        await stub.when { try await $0.load() }.then { () async throws -> String in
            await Task.yield()
            throw ThrowingProbeError(value: -1)
        }
        await stub.when { await $0.advance(any()) }.then { (value: String) async throws -> String in
            await Task.yield()
            return value.uppercased()
        }

        let probe: any EffectfulBoundAssociatedTypeProbe<String> = stub()
        #expect(await probe.advance("value") == "VALUE")
        let error = await #expect(throws: ThrowingProbeError.self) {
            _ = try await probe.load()
        }
        #expect(error?.value == -1)
    }

    @Test func explicitAsyncDependentRequirementsDoNotNeedAConformer() async throws {
        typealias ProbeStub = Stub<any ExplicitEffectfulBoundAssociatedTypeProbe<Int>>
        let element = ProbeStub.Requirement.Value.associatedType(named: "Element")
        let stub = try ProbeStub(
            .method(returning: element, isThrowing: true, isAsync: true),
            .getter(element, isThrowing: true, isAsync: true)
        )
        await stub.when { try await $0.load() }.thenReturn(41)
        await stub.when { try await $0.current }.thenReturn(42)

        #expect(try await stub().load() == 41)
        #expect(try await stub().current == 42)
    }

    @Test func x86AsyncDependentRegisterBoundaryCountsIndirectWords() {
        let element = WitnessValueConvention.associatedType(name: "Element")
        let armSupported = MethodDescriptor(
            kind: .method,
            name: "requirement_0",
            index: 0,
            argumentTypes: Array(repeating: Int.self, count: 5),
            returnType: Int.self,
            argumentConventions: Array(repeating: element, count: 5),
            returnConvention: element,
            isAsync: true
        )
        #expect(unsupportedRuntimeReason(for: armSupported, architecture: .arm64) == nil)
        #expect(unsupportedRuntimeReason(for: armSupported, architecture: .x86_64) != nil)

        let firstX86Spill = MethodDescriptor(
            kind: .method,
            name: "requirement_0",
            index: 0,
            argumentTypes: Array(repeating: Int.self, count: 4),
            returnType: Int.self,
            argumentConventions: Array(repeating: element, count: 4),
            returnConvention: element,
            isAsync: true
        )
        #expect(unsupportedRuntimeReason(for: firstX86Spill, architecture: .x86_64) != nil)

        let x86Supported = MethodDescriptor(
            kind: .method,
            name: "requirement_0",
            index: 0,
            argumentTypes: Array(repeating: Int.self, count: 3),
            returnType: Int.self,
            argumentConventions: Array(repeating: element, count: 3),
            returnConvention: element,
            isAsync: true
        )
        #expect(unsupportedRuntimeReason(for: x86Supported, architecture: .x86_64) == nil)
    }

    @Test func unsupportedAssociatedShapesFailClosed() {
        _ = RealNestedBoundAssociatedTypeProbe()
        #expect(throws: StubError.self) {
            _ = try Stub<any BoundAssociatedTypeProbe>()
        }
    }

    @Test func concreteTypedErrorsWorkWithDependentResults() throws {
        _ = RealTypedThrowingBoundAssociatedTypeProbe()
        let success = try Stub<any TypedThrowingBoundAssociatedTypeProbe<Int>>()
        let method = try #require(success.recorder.runtimeMethod(for: 0))
        #expect(method.typedErrorUsesIndirectResultSlot)
        success.when { try $0.load() }.thenReturn(41)
        #expect(try success().load() == 41)

        let failure = try Stub<any TypedThrowingBoundAssociatedTypeProbe<Int>>()
        failure.when { try $0.load() }.then {
            () throws -> Int in
            throw ThrowingProbeError(value: 42)
        }
        let error = #expect(throws: ThrowingProbeError.self) {
            _ = try failure().load()
        }
        #expect(error?.value == 42)

        _ = RealTypedThrowingArrayBoundAssociatedTypeProbe()
        let array = try Stub<any TypedThrowingArrayBoundAssociatedTypeProbe<Int>>()
        let arrayMethod = try #require(array.recorder.runtimeMethod(for: 0))
        #expect(arrayMethod.typedErrorUsesIndirectResultSlot == false)
        array.when { try $0.load() }.thenReturn([1, 2, 3])
        #expect(try array().load() == [1, 2, 3])
    }
}

private func exerciseDependentSetter(
    source: BoundAssociatedTypeRequirementSource
) throws -> (WeakReference<BoundAssociatedTypeBox>, LockedCounter) {
    typealias Probe = any BoundAssociatedTypeSetterProbe<BoundAssociatedTypeBox>
    typealias ProbeStub = Stub<Probe>
    let element = ProbeStub.Requirement.Value.associatedType(named: "Element")
    let stub =
        switch source {
            case .automatic:
                try ProbeStub()
            case .explicit:
                try ProbeStub(.getter(element), .setter(element))
        }
    let getter = try #require(stub.recorder.runtimeMethod(for: 0))
    let setter = try #require(stub.recorder.runtimeMethod(for: 1))
    #expect(getter.returnConvention == .associatedType(name: "Element"))
    #expect(setter.argumentConventions == [.associatedType(name: "Element")])
    #expect(setter.argumentOwnerships == [.owned])

    let returned = BoundAssociatedTypeBox()
    let placeholder = BoundAssociatedTypeBox()
    stub.when(returning: returned) { $0.value }.thenReturn(returned)
    stub.when { $0.value = any(using: placeholder) }
    var probe: Probe = stub()
    #expect(probe.value === returned)

    let deinitCounter = LockedCounter()
    var assigned: BoundAssociatedTypeBox? = BoundAssociatedTypeBox(
        deinitCounter: deinitCounter
    )
    let weakReference = WeakReference(assigned)
    probe.value = try #require(assigned)
    assigned = nil

    #expect(weakReference.value != nil)
    stub.verify { $0.value = any(using: placeholder) }
    return (weakReference, deinitCounter)
}

private func exerciseConsumingDependentArguments(
    source: BoundAssociatedTypeRequirementSource
) async throws -> (
    sync: WeakReference<BoundAssociatedTypeBox>,
    async: WeakReference<BoundAssociatedTypeBox>,
    syncCounter: LockedCounter,
    asyncCounter: LockedCounter
) {
    typealias Probe = any ConsumingBoundAssociatedTypeProbe<BoundAssociatedTypeBox>
    typealias ProbeStub = Stub<Probe>
    let value = ProbeStub.Requirement.Value.self
    let consumingElement = value.consumingAssociatedType(named: "Element")
    let void = value.concrete(Void.self)
    let stub =
        switch source {
            case .automatic:
                try ProbeStub()
            case .explicit:
                try ProbeStub(
                    .method(consumingElement, returning: void),
                    .method(consumingElement, returning: void, isAsync: true)
                )
        }
    let syncMethod = try #require(stub.recorder.runtimeMethod(for: 0))
    let asyncMethod = try #require(stub.recorder.runtimeMethod(for: 1))
    #expect(syncMethod.argumentOwnerships == [.owned])
    #expect(asyncMethod.argumentOwnerships == [.owned])

    let placeholder = BoundAssociatedTypeBox()
    stub.when { $0.consume(any(using: placeholder)) }
    await stub.when {
        await $0.consumeAsync(any(using: placeholder))
    }.then { (_: BoundAssociatedTypeBox) async in
        await Task.yield()
    }

    let probe: Probe = stub()
    let syncCounter = LockedCounter()
    var syncValue: BoundAssociatedTypeBox? = BoundAssociatedTypeBox(
        deinitCounter: syncCounter
    )
    let weakSync = WeakReference(syncValue)
    probe.consume(try #require(syncValue))
    syncValue = nil
    #expect(weakSync.value != nil)

    let asyncCounter = LockedCounter()
    var asyncValue: BoundAssociatedTypeBox? = BoundAssociatedTypeBox(
        deinitCounter: asyncCounter
    )
    let weakAsync = WeakReference(asyncValue)
    await probe.consumeAsync(try #require(asyncValue))
    asyncValue = nil
    #expect(weakAsync.value != nil)

    stub.verify { $0.consume(any(using: placeholder)) }
    await stub.verify { await $0.consumeAsync(any(using: placeholder)) }
    return (weakSync, weakAsync, syncCounter, asyncCounter)
}
