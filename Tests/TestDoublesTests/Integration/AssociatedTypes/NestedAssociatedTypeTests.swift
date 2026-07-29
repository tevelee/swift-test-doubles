import InternalRuntimeContract
import Testing
@testable import TestDoubles

// swiftlint:disable file_length

// Runtime-discovery fixtures must remain module-internal. With a private
// protocol, release whole-module optimization can remove its only declared
// conformance and bypass fabricated witness-table dispatch.
protocol NestedAssociatedTypeProbe<Element> {
    associatedtype Element

    func transform(optional value: Element?) -> Element?
    func transform(array values: [Element]) -> [Element]
    var current: Element? { get }
}

struct RealNestedAssociatedTypeProbe: NestedAssociatedTypeProbe {
    func transform(optional value: Int?) -> Int? { value }
    func transform(array values: [Int]) -> [Int] { values }
    var current: Int? { 0 }
}

private protocol ExplicitNestedAssociatedTypeProbe<Element> {
    associatedtype Element

    func transform(optional value: Element?) -> Element?
    func transform(array values: [Element]) -> [Element]
    var current: Element? { get }
}

protocol SetNestedAssociatedTypeProbe<Element> {
    associatedtype Element: Hashable

    func transform(set values: Set<Element>) -> Set<Element>
}

struct RealSetNestedAssociatedTypeProbe:
    SetNestedAssociatedTypeProbe
{
    func transform(set values: Set<Int>) -> Set<Int> { values }
}

private protocol ExplicitSetNestedAssociatedTypeProbe<Element> {
    associatedtype Element: Hashable

    func transform(set values: Set<Element>) -> Set<Element>
}

protocol DictionaryNestedAssociatedTypeProbe<Key, Value> {
    associatedtype Key: Hashable
    associatedtype Value

    func transform(values: [String: Value]) -> [String: Value]
    func transform(keys: [Key: Int]) -> [Key: Int]
    func transform(entries: [Key: Value]) -> [Key: Value]
}

struct RealDictionaryNestedAssociatedTypeProbe:
    DictionaryNestedAssociatedTypeProbe
{
    func transform(values: [String: String]) -> [String: String] { values }
    func transform(keys: [String: Int]) -> [String: Int] { keys }
    func transform(entries: [String: String]) -> [String: String] { entries }
}

private protocol ExplicitDictionaryNestedAssociatedTypeProbe<Key, Value> {
    associatedtype Key: Hashable
    associatedtype Value

    func transform(values: [String: Value]) -> [String: Value]
    func transform(keys: [Key: Int]) -> [Key: Int]
    func transform(entries: [Key: Value]) -> [Key: Value]
}

private protocol ExplicitNonHashableAssociatedTypeProbe<Element> {
    associatedtype Element

    func transform(_ value: Element) -> Element
}

private final class NonHashableAssociatedTypeValue {}

protocol RecursiveNestedAssociatedTypeProbe<Element> {
    associatedtype Element: Hashable

    func transform(opaque value: Element??) -> Element??
    func transform(optionalArray value: [Element]?) -> [Element]?
    func transform(arrayOptionals value: [Element?]) -> [Element?]
    func transform(set value: Set<Element?>) -> Set<Element?>
    func transform(
        dictionary value: [Set<Element?>?: [String: [Element?]]]
    ) -> [Set<Element?>?: [String: [Element?]]]
}

struct RealRecursiveNestedAssociatedTypeProbe:
    RecursiveNestedAssociatedTypeProbe
{
    func transform(opaque value: Int??) -> Int?? { value }
    func transform(optionalArray value: [Int]?) -> [Int]? { value }
    func transform(arrayOptionals value: [Int?]) -> [Int?] { value }
    func transform(set value: Set<Int?>) -> Set<Int?> { value }
    func transform(
        dictionary value: [Set<Int?>?: [String: [Int?]]]
    ) -> [Set<Int?>?: [String: [Int?]]] {
        value
    }
}

protocol ConsumingNestedAssociatedTypeProbe<Element> {
    associatedtype Element

    func consume(optional value: consuming Element?)
    func consume(array values: consuming [Element])
    func consumeAsync(optional value: consuming Element?) async
    func consumeAsync(array values: consuming [Element]) async
}

struct RealConsumingNestedAssociatedTypeProbe:
    ConsumingNestedAssociatedTypeProbe
{
    func consume(optional value: consuming NestedAssociatedTypeBox?) {}
    func consume(array values: consuming [NestedAssociatedTypeBox]) {}
    func consumeAsync(optional value: consuming NestedAssociatedTypeBox?) async {}
    func consumeAsync(array values: consuming [NestedAssociatedTypeBox]) async {}
}

final class NestedAssociatedTypeBox: @unchecked Sendable {
    private let deinitCounter: LockedCounter?

    init(deinitCounter: LockedCounter? = nil) {
        self.deinitCounter = deinitCounter
    }

    deinit {
        deinitCounter?.increment()
    }
}

enum NestedAssociatedRequirementSource: CaseIterable, Sendable {
    case automatic
    case explicit
}

protocol NestedAssociatedInitializerProbe<Element> {
    associatedtype Element

    init(values: [Element])
}

struct RealNestedAssociatedInitializerProbe:
    NestedAssociatedInitializerProbe
{
    init(values: [Int]) {}
}

@inline(never)
private func useLinkedNestedAssociatedTypeProbe(
    _ value: any NestedAssociatedTypeProbe<Int>
) -> Int? {
    value.transform(optional: 0)
}

@inline(never)
private func useLinkedNestedAssociatedInitializerProbe(
    _ value: any NestedAssociatedInitializerProbe<Int>
) -> Bool {
    type(of: value).init(values: [1]) is RealNestedAssociatedInitializerProbe
}

@inline(never)
private func useLinkedRecursiveNestedAssociatedTypeProbe(
    _ value: any RecursiveNestedAssociatedTypeProbe<Int>
) -> [Int]? {
    value.transform(optionalArray: [1])
}

struct NestedAssociatedTypeTests {
    @Test func automaticDiscoverySupportsOptionalArrayAndGetter() throws {
        #expect(useLinkedNestedAssociatedTypeProbe(RealNestedAssociatedTypeProbe()) == 0)
        let stub = try Stub<any NestedAssociatedTypeProbe<Int>>()
        let optional = try #require(stub.recorder.runtimeMethod(for: 0))
        let array = try #require(stub.recorder.runtimeMethod(for: 1))
        let getter = try #require(stub.recorder.runtimeMethod(for: 2))

        assertDependentIndirect(
            optional,
            argumentType: Int?.self,
            returnType: Int?.self
        )
        assertDependentArray(
            array,
            argumentType: [Int].self,
            returnType: [Int].self
        )
        #expect(getter.argumentTypes.isEmpty)
        #expect(ObjectIdentifier(getter.returnType) == ObjectIdentifier(Int?.self))
        #expect(getter.returnConvention == .associatedType(name: "Element"))
        #expect(
            getter.returnAssociatedTypeUse == .associatedType(named: "Element")
        )

        stub.onCall { $0.transform(optional: Match.any()) }.then { (value: Int?) in
            value.map { $0 + 1 }
        }
        stub.onCall { $0.transform(array: Match.any()) }.then { (values: [Int]) in
            values.map { $0 + 1 }
        }
        stub.onCall { $0.current }.thenReturn(42)
        let probe: any NestedAssociatedTypeProbe<Int> = stub()

        #expect(probe.transform(optional: nil) == nil)
        #expect(probe.transform(optional: 41) == 42)
        #expect(probe.transform(array: [1, 2, 3]) == [2, 3, 4])
        #expect(probe.current == 42)
    }

    @Test func explicitRequirementsSupportOptionalArrayAndGetter() throws {
        typealias ProbeStub = Stub<any ExplicitNestedAssociatedTypeProbe<String>>
        let optional = ProbeStub.Requirement.Value
            .optionalAssociatedType(named: "Element")
        let array = ProbeStub.Requirement.Value
            .arrayOfAssociatedType(named: "Element")
        let stub = try ProbeStub(
            .method(optional, returning: optional),
            .method(array, returning: array),
            .getter(optional)
        )

        let optionalDescriptor = try #require(stub.recorder.runtimeMethod(for: 0))
        let arrayDescriptor = try #require(stub.recorder.runtimeMethod(for: 1))
        assertDependentIndirect(
            optionalDescriptor,
            argumentType: String?.self,
            returnType: String?.self
        )
        assertDependentArray(
            arrayDescriptor,
            argumentType: [String].self,
            returnType: [String].self
        )

        stub.onCall { $0.transform(optional: Match.any()) }.then { (value: String?) in
            value?.uppercased()
        }
        stub.onCall { $0.transform(array: Match.any()) }.then { (values: [String]) in
            values.map { $0.uppercased() }
        }
        stub.onCall { $0.current }.thenReturn("current")
        let probe: any ExplicitNestedAssociatedTypeProbe<String> = stub()

        #expect(probe.transform(optional: nil) == nil)
        #expect(probe.transform(optional: "value") == "VALUE")
        #expect(probe.transform(array: ["one", "two"]) == ["ONE", "TWO"])
        #expect(probe.current == "current")
    }

    @Test func explicitValidationRejectsConcreteContainerConventions() {
        #expect(useLinkedNestedAssociatedTypeProbe(RealNestedAssociatedTypeProbe()) == 0)
        typealias ProbeStub = Stub<any NestedAssociatedTypeProbe<Int>>
        let optional = ProbeStub.Requirement.Value
            .optionalAssociatedType(named: "Element")
        let array = ProbeStub.Requirement.Value
            .arrayOfAssociatedType(named: "Element")

        expectRequirementMismatch(at: 0) {
            _ = try ProbeStub(
                .method(Int?.self, returning: Int?.self),
                .method(array, returning: array),
                .getter(optional)
            )
        }
        expectRequirementMismatch(at: 1) {
            _ = try ProbeStub(
                .method(optional, returning: optional),
                .method([Int].self, returning: [Int].self),
                .getter(optional)
            )
        }
    }

    @Test func automaticDiscoverySupportsSet() throws {
        #expect(RealSetNestedAssociatedTypeProbe().transform(set: [0]) == [0])
        typealias ProbeStub = Stub<any SetNestedAssociatedTypeProbe<Int>>
        let stub = try ProbeStub()
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        assertDependentSet(
            method,
            argumentType: Set<Int>.self,
            returnType: Set<Int>.self
        )

        stub.onCall { $0.transform(set: Match.any()) }.then { (values: Set<Int>) in
            Set(values.map { $0 + 1 })
        }
        let probe: any SetNestedAssociatedTypeProbe<Int> = stub()

        #expect(probe.transform(set: [1, 2, 3]) == [2, 3, 4])
        stub.verify { $0.transform(set: Match.equal([1, 2, 3])) }
    }

    @Test func explicitRequirementsSupportSet() throws {
        typealias ProbeStub = Stub<any ExplicitSetNestedAssociatedTypeProbe<String>>
        let set = ProbeStub.Requirement.Value
            .setOfAssociatedType(named: "Element")
        let stub = try ProbeStub(.method(set, returning: set))
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        assertDependentSet(
            method,
            argumentType: Set<String>.self,
            returnType: Set<String>.self
        )

        stub.onCall { $0.transform(set: Match.any()) }.then { (values: Set<String>) in
            Set(values.map { $0.uppercased() })
        }
        let probe: any ExplicitSetNestedAssociatedTypeProbe<String> = stub()

        #expect(probe.transform(set: ["one", "two"]) == ["ONE", "TWO"])
        stub.verify { $0.transform(set: Match.equal(["one", "two"])) }
    }

    @Test func explicitValidationRejectsConcreteSetConvention() {
        #expect(RealSetNestedAssociatedTypeProbe().transform(set: [0]) == [0])
        typealias ProbeStub = Stub<any SetNestedAssociatedTypeProbe<Int>>

        expectRequirementMismatch(at: 0) {
            _ = try ProbeStub(
                .method(Set<Int>.self, returning: Set<Int>.self)
            )
        }
    }

    @Test func automaticDiscoverySupportsDictionaryKeyAndValuePositions() throws {
        _ = RealDictionaryNestedAssociatedTypeProbe()
        typealias Probe = any DictionaryNestedAssociatedTypeProbe<String, String>
        let stub = try Stub<Probe>()
        let values = try #require(stub.recorder.runtimeMethod(for: 0))
        let keys = try #require(stub.recorder.runtimeMethod(for: 1))
        let entries = try #require(stub.recorder.runtimeMethod(for: 2))

        assertDependentDictionary(
            values,
            type: [String: String].self,
            associatedTypeNames: ["Value"]
        )
        assertDependentDictionary(
            keys,
            type: [String: Int].self,
            associatedTypeNames: ["Key"]
        )
        assertDependentDictionary(
            entries,
            type: [String: String].self,
            associatedTypeNames: ["Key", "Value"]
        )

        stub.onCall { $0.transform(values: Match.any()) }.then { (values: [String: String]) in
            values.mapValues { $0.uppercased() }
        }
        stub.onCall { $0.transform(keys: Match.any()) }.then { (keys: [String: Int]) in
            keys.mapValues { $0 + 1 }
        }
        stub.onCall { $0.transform(entries: Match.any()) }.then { (entries: [String: String]) in
            entries.mapValues { $0.uppercased() }
        }
        let probe: Probe = stub()

        #expect(probe.transform(values: ["value": "one"]) == ["value": "ONE"])
        #expect(probe.transform(keys: ["value": 1]) == ["value": 2])
        #expect(probe.transform(entries: ["value": "two"]) == ["value": "TWO"])
    }

    @Test func explicitRequirementsSupportDictionaryWithoutLinkedConformer() throws {
        typealias ProbeStub = Stub<
            any ExplicitDictionaryNestedAssociatedTypeProbe<String, String>
        >
        let values = ProbeStub.Requirement.Value.dictionary(
            key: String.self,
            valueAssociatedTypeNamed: "Value"
        )
        let keys = ProbeStub.Requirement.Value.dictionary(
            keyAssociatedTypeNamed: "Key",
            value: Int.self
        )
        let entries = ProbeStub.Requirement.Value.dictionary(
            keyAssociatedTypeNamed: "Key",
            valueAssociatedTypeNamed: "Value"
        )
        let stub = try ProbeStub(
            .method(values, returning: values),
            .method(keys, returning: keys),
            .method(entries, returning: entries)
        )

        assertDependentDictionary(
            try #require(stub.recorder.runtimeMethod(for: 0)),
            type: [String: String].self,
            associatedTypeNames: ["Value"]
        )
        assertDependentDictionary(
            try #require(stub.recorder.runtimeMethod(for: 1)),
            type: [String: Int].self,
            associatedTypeNames: ["Key"]
        )
        assertDependentDictionary(
            try #require(stub.recorder.runtimeMethod(for: 2)),
            type: [String: String].self,
            associatedTypeNames: ["Key", "Value"]
        )

        stub.onCall { $0.transform(values: Match.any()) }.thenReturn(["explicit": "value"])
        stub.onCall { $0.transform(keys: Match.any()) }.thenReturn(["explicit": 42])
        stub.onCall { $0.transform(entries: Match.any()) }.thenReturn(["explicit": "entry"])
        let probe = stub()

        #expect(probe.transform(values: [:]) == ["explicit": "value"])
        #expect(probe.transform(keys: [:]) == ["explicit": 42])
        #expect(probe.transform(entries: [:]) == ["explicit": "entry"])
    }

    @Test func explicitValidationPreservesDictionaryDependencyPositions() {
        _ = RealDictionaryNestedAssociatedTypeProbe()
        typealias ProbeStub = Stub<
            any DictionaryNestedAssociatedTypeProbe<String, String>
        >
        let wrongValues = ProbeStub.Requirement.Value.dictionary(
            keyAssociatedTypeNamed: "Key",
            value: String.self
        )
        let keys = ProbeStub.Requirement.Value.dictionary(
            keyAssociatedTypeNamed: "Key",
            value: Int.self
        )
        let entries = ProbeStub.Requirement.Value.dictionary(
            keyAssociatedTypeNamed: "Key",
            valueAssociatedTypeNamed: "Value"
        )

        expectDictionaryRequirementMismatch(at: 0) {
            _ = try ProbeStub(
                .method(wrongValues, returning: wrongValues),
                .method(keys, returning: keys),
                .method(entries, returning: entries)
            )
        }
    }

    @Test func explicitSetRequiresHashableAssociatedTypeBinding() {
        typealias ProbeStub = Stub<
            any ExplicitNonHashableAssociatedTypeProbe<NonHashableAssociatedTypeValue>
        >
        let set = ProbeStub.Requirement.Value
            .setOfAssociatedType(named: "Element")

        expectStubError {
            _ = try ProbeStub(.method(set, returning: set))
        } matching: { error in
            guard case .unsupportedProtocolShape(_, let reason) = error else {
                return false
            }
            return reason.contains("does not conform to Hashable")
                && reason.contains("NonHashableAssociatedTypeValue")
        }
    }

    @Test func automaticDiscoverySupportsRecursiveStandardLibraryContainers() throws {
        #expect(
            useLinkedRecursiveNestedAssociatedTypeProbe(
                RealRecursiveNestedAssociatedTypeProbe()
            ) == [1]
        )
        typealias NestedDictionary = [Set<Int?>?: [String: [Int?]]]
        let stub = try Stub<any RecursiveNestedAssociatedTypeProbe<Int>>()

        try assertRecursiveDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            type: Optional<Int?>.self,
            associatedTypeNames: ["Element"]
        )
        try assertRecursiveDescriptor(
            #require(stub.recorder.runtimeMethod(for: 1)),
            type: Optional<[Int]>.self,
            associatedTypeNames: ["Element"]
        )
        try assertRecursiveDescriptor(
            #require(stub.recorder.runtimeMethod(for: 2)),
            type: Array<Int?>.self,
            associatedTypeNames: ["Element"]
        )
        try assertRecursiveDescriptor(
            #require(stub.recorder.runtimeMethod(for: 3)),
            type: Set<Int?>.self,
            associatedTypeNames: ["Element"]
        )
        try assertRecursiveDescriptor(
            #require(stub.recorder.runtimeMethod(for: 4)),
            type: NestedDictionary.self,
            associatedTypeNames: ["Element"]
        )
    }

    @Test func explicitRecursiveSchemasMatchAutomaticDiscovery() throws {
        _ = RealRecursiveNestedAssociatedTypeProbe()
        typealias ProbeStub = Stub<any RecursiveNestedAssociatedTypeProbe<Int>>
        let value = ProbeStub.Requirement.Value.self
        let element = value.associatedType(named: "Element")
        let optionalElement = value.optional(wrapping: element)
        let opaque = value.optional(wrapping: optionalElement)
        let optionalArray = value.optional(wrapping: value.array(of: element))
        let arrayOptionals = value.array(of: optionalElement)
        let set = value.set(of: optionalElement)
        let dictionary = value.dictionary(
            key: value.optional(wrapping: set),
            value: value.dictionary(
                key: value.concrete(String.self),
                value: arrayOptionals
            )
        )
        let stub = try ProbeStub(
            .method(opaque, returning: opaque),
            .method(optionalArray, returning: optionalArray),
            .method(arrayOptionals, returning: arrayOptionals),
            .method(set, returning: set),
            .method(dictionary, returning: dictionary)
        )

        let opaqueDescriptor = try #require(
            stub.recorder.runtimeMethod(for: 0)
        )
        let optionalArrayDescriptor = try #require(
            stub.recorder.runtimeMethod(for: 1)
        )
        #expect(opaqueDescriptor.returnAssociatedTypeUse.names == ["Element"])
        #expect(optionalArrayDescriptor.returnAssociatedTypeUse.names == ["Element"])

        stub.onCall { $0.transform(optionalArray: Match.any()) }
            .thenReturn([42])
        let probe: any RecursiveNestedAssociatedTypeProbe<Int> = stub()
        #expect(probe.transform(optionalArray: nil) == [42])
    }

    @Test func recursiveSetAndDictionaryKeysRequireHashableMetadata() {
        typealias ProbeStub = Stub<
            any ExplicitNonHashableAssociatedTypeProbe<NonHashableAssociatedTypeValue>
        >
        let value = ProbeStub.Requirement.Value.self
        let element = value.associatedType(named: "Element")
        let nestedSet = value.set(of: value.optional(wrapping: element))
        let nestedDictionary = value.dictionary(
            key: value.array(of: element),
            value: value.concrete(Int.self)
        )

        for schema in [nestedSet, nestedDictionary] {
            expectStubError {
                _ = try ProbeStub(.method(schema, returning: schema))
            } matching: { error in
                guard case .unsupportedProtocolShape(_, let reason) = error else {
                    return false
                }
                return reason.contains("does not conform to Hashable")
                    && reason.contains("NonHashableAssociatedTypeValue")
            }
        }
    }

    @Test(arguments: NestedAssociatedRequirementSource.allCases)
    func consumingOptionalAndArrayPreserveOwnedStorage(
        source: NestedAssociatedRequirementSource
    ) async throws {
        _ = RealConsumingNestedAssociatedTypeProbe()
        let lifetimes = try await exerciseConsumingNestedAssociatedTypes(source: source)

        for lifetime in lifetimes {
            #expect(lifetime.reference.value == nil)
            #expect(lifetime.counter.value == 1)
        }
    }

    @Test func consumingTransformRejectsIndependentValuesAndResults() {
        _ = RealNestedAssociatedTypeProbe()
        typealias ProbeStub = Stub<any NestedAssociatedTypeProbe<Int>>
        let value = ProbeStub.Requirement.Value.self
        let concreteOptional = value.concrete(Int?.self)
        let optional = value.optionalAssociatedType(named: "Element")
        let array = value.arrayOfAssociatedType(named: "Element")

        #expect(throws: StubError.self) {
            _ = try ProbeStub(
                .method(concreteOptional.consuming(), returning: optional),
                .method(array, returning: array),
                .getter(optional)
            )
        }
        #expect(throws: StubError.self) {
            _ = try ProbeStub(
                .method(optional, returning: optional.consuming()),
                .method(array, returning: array),
                .getter(optional)
            )
        }
    }

    @Test func automaticDiscoverySupportsArrayAssociatedTypeInitializers() throws {
        #expect(
            useLinkedNestedAssociatedInitializerProbe(
                RealNestedAssociatedInitializerProbe(values: [])
            )
        )
        typealias ProbeStub = Stub<any NestedAssociatedInitializerProbe<Int>>
        let stub = try ProbeStub()
        let initializer = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(initializer.kind == .initializer)
        #expect(initializer.argumentTypes.count == 1)
        #expect(
            initializer.argumentTypes.first.map(ObjectIdentifier.init)
                == ObjectIdentifier([Int].self)
        )
        #expect(initializer.argumentConventions == [.concrete])
        #expect(
            initializer.argumentAssociatedTypeUses == [.associatedType(named: "Element")]
        )
        #expect(initializer.argumentOwnerships == [.owned])
        #expect(initializer.returnConvention == .selfType)

        stub.onCall(initializer: {
            type(of: $0).init(values: Match.any())
        }).thenInitialize()
        let seed: any NestedAssociatedInitializerProbe<Int> = stub()
        _ = type(of: seed).init(values: [1, 2, 3])

        stub.verify {
            type(of: $0).init(values: Match.equal([1, 2, 3]))
        }
    }

    @Test func arrayAssociatedTypeInitializerArgumentUsesOwnedStorage() throws {
        typealias Probe = any NestedAssociatedInitializerProbe<NestedAssociatedTypeBox>
        let stub = try Stub<Probe>()
        let placeholder = NestedAssociatedTypeBox()
        stub.onCall(initializer: {
            type(of: $0).init(values: Match.any(using: [placeholder]))
        }).thenInitialize()
        let seed: Probe = stub()
        var (value, lifetime) = makeOptionalNestedAssociatedTypeBox()

        _ = type(of: seed).init(values: [try #require(value)])
        value = nil

        #expect(lifetime.reference.value != nil)
        #expect(lifetime.counter.value == 0)
        stub.clearRecordedInvocations()
        #expect(lifetime.reference.value == nil)
        #expect(lifetime.counter.value == 1)
    }
}

private struct NestedAssociatedLifetime {
    let reference: WeakReference<NestedAssociatedTypeBox>
    let counter: LockedCounter
}

private func exerciseConsumingNestedAssociatedTypes(
    source: NestedAssociatedRequirementSource
) async throws -> [NestedAssociatedLifetime] {
    typealias Probe = any ConsumingNestedAssociatedTypeProbe<NestedAssociatedTypeBox>
    typealias ProbeStub = Stub<Probe>
    let value = ProbeStub.Requirement.Value.self
    let optional = value.optionalAssociatedType(named: "Element").consuming()
    let array = value.arrayOfAssociatedType(named: "Element").consuming()
    let void = value.concrete(Void.self)
    let stub =
        switch source {
            case .automatic:
                try ProbeStub()
            case .explicit:
                try ProbeStub(
                    .method(optional, returning: void),
                    .method(array, returning: void),
                    .method(optional, returning: void, isAsync: true),
                    .method(array, returning: void, isAsync: true)
                )
        }

    try assertConsumingNestedDescriptor(
        #require(stub.recorder.runtimeMethod(for: 0)),
        type: NestedAssociatedTypeBox?.self,
        convention: .associatedType(name: "Element"),
        isAsync: false
    )
    try assertConsumingNestedDescriptor(
        #require(stub.recorder.runtimeMethod(for: 1)),
        type: [NestedAssociatedTypeBox].self,
        convention: .concrete,
        isAsync: false
    )
    try assertConsumingNestedDescriptor(
        #require(stub.recorder.runtimeMethod(for: 2)),
        type: NestedAssociatedTypeBox?.self,
        convention: .associatedType(name: "Element"),
        isAsync: true
    )
    try assertConsumingNestedDescriptor(
        #require(stub.recorder.runtimeMethod(for: 3)),
        type: [NestedAssociatedTypeBox].self,
        convention: .concrete,
        isAsync: true
    )

    let placeholder = NestedAssociatedTypeBox()
    stub.onCall { $0.consume(optional: Match.any(using: Optional(placeholder))) }.thenDoNothing()
    stub.onCall { $0.consume(array: Match.any(using: [placeholder])) }.thenDoNothing()
    await stub.onCall {
        await $0.consumeAsync(optional: Match.any(using: Optional(placeholder)))
    }.thenDoNothing()
    await stub.onCall {
        await $0.consumeAsync(array: Match.any(using: [placeholder]))
    }.thenDoNothing()

    let probe: Probe = stub()
    var (optionalSyncValue, optionalSyncLifetime) = makeOptionalNestedAssociatedTypeBox()
    probe.consume(optional: optionalSyncValue)
    optionalSyncValue = nil
    #expect(optionalSyncLifetime.reference.value != nil)

    var (arraySyncValue, arraySyncLifetime) = makeArrayNestedAssociatedTypeBox()
    probe.consume(array: arraySyncValue)
    arraySyncValue.removeAll()
    #expect(arraySyncLifetime.reference.value != nil)

    var (optionalAsyncValue, optionalAsyncLifetime) = makeOptionalNestedAssociatedTypeBox()
    await probe.consumeAsync(optional: optionalAsyncValue)
    optionalAsyncValue = nil
    #expect(optionalAsyncLifetime.reference.value != nil)

    var (arrayAsyncValue, arrayAsyncLifetime) = makeArrayNestedAssociatedTypeBox()
    await probe.consumeAsync(array: arrayAsyncValue)
    arrayAsyncValue.removeAll()
    #expect(arrayAsyncLifetime.reference.value != nil)

    return [
        optionalSyncLifetime,
        arraySyncLifetime,
        optionalAsyncLifetime,
        arrayAsyncLifetime
    ]
}

private func assertConsumingNestedDescriptor<T>(
    _ method: RuntimeMethod,
    type: T.Type,
    convention: RuntimeValueConvention,
    isAsync: Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let argumentType = try #require(method.argumentTypes.first)
    #expect(method.argumentTypes.count == 1, sourceLocation: sourceLocation)
    #expect(
        ObjectIdentifier(argumentType) == ObjectIdentifier(type),
        sourceLocation: sourceLocation
    )
    #expect(method.argumentConventions == [convention], sourceLocation: sourceLocation)
    #expect(
        method.argumentAssociatedTypeUses == [.associatedType(named: "Element")],
        sourceLocation: sourceLocation
    )
    #expect(method.argumentOwnerships == [.owned], sourceLocation: sourceLocation)
    #expect(method.isAsync == isAsync, sourceLocation: sourceLocation)
}

private func makeOptionalNestedAssociatedTypeBox() -> (
    value: NestedAssociatedTypeBox?,
    lifetime: NestedAssociatedLifetime
) {
    let counter = LockedCounter()
    let value = NestedAssociatedTypeBox(deinitCounter: counter)
    let reference = WeakReference(value)
    return (
        value,
        NestedAssociatedLifetime(reference: reference, counter: counter)
    )
}

private func makeArrayNestedAssociatedTypeBox() -> (
    values: [NestedAssociatedTypeBox],
    lifetime: NestedAssociatedLifetime
) {
    let counter = LockedCounter()
    let value = NestedAssociatedTypeBox(deinitCounter: counter)
    let reference = WeakReference(value)
    return (
        [value],
        NestedAssociatedLifetime(reference: reference, counter: counter)
    )
}

private func assertRecursiveDescriptor<Value>(
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
}

private func assertDependentIndirect<Argument, Result>(
    _ method: RuntimeMethod,
    argumentType: Argument.Type,
    returnType: Result.Type,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(method.argumentTypes.count == 1, sourceLocation: sourceLocation)
    guard
        let actualArgumentType = method.argumentTypes.first,
        let argumentConvention = method.argumentConventions.first
    else {
        return
    }
    #expect(
        ObjectIdentifier(actualArgumentType) == ObjectIdentifier(argumentType),
        sourceLocation: sourceLocation
    )
    #expect(
        ObjectIdentifier(method.returnType) == ObjectIdentifier(returnType),
        sourceLocation: sourceLocation
    )
    #expect(
        argumentConvention == .associatedType(name: "Element"),
        sourceLocation: sourceLocation
    )
    #expect(
        method.argumentAssociatedTypeUses == [.associatedType(named: "Element")],
        sourceLocation: sourceLocation
    )
    #expect(
        method.returnConvention == .associatedType(name: "Element"),
        sourceLocation: sourceLocation
    )
    #expect(
        method.returnAssociatedTypeUse == .associatedType(named: "Element"),
        sourceLocation: sourceLocation
    )
}

private func assertDependentArray<Argument, Result>(
    _ method: RuntimeMethod,
    argumentType: Argument.Type,
    returnType: Result.Type,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(method.argumentTypes.count == 1, sourceLocation: sourceLocation)
    guard
        let actualArgumentType = method.argumentTypes.first,
        let argumentConvention = method.argumentConventions.first
    else {
        return
    }
    #expect(
        ObjectIdentifier(actualArgumentType) == ObjectIdentifier(argumentType),
        sourceLocation: sourceLocation
    )
    #expect(
        ObjectIdentifier(method.returnType) == ObjectIdentifier(returnType),
        sourceLocation: sourceLocation
    )
    #expect(argumentConvention == .concrete, sourceLocation: sourceLocation)
    #expect(method.returnConvention == .concrete, sourceLocation: sourceLocation)
    #expect(
        method.argumentAssociatedTypeUses == [.associatedType(named: "Element")],
        sourceLocation: sourceLocation
    )
    #expect(
        method.returnAssociatedTypeUse == .associatedType(named: "Element"),
        sourceLocation: sourceLocation
    )
}

private func assertDependentSet<Argument, Result>(
    _ method: RuntimeMethod,
    argumentType: Argument.Type,
    returnType: Result.Type,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(method.argumentTypes.count == 1, sourceLocation: sourceLocation)
    guard
        let actualArgumentType = method.argumentTypes.first,
        let argumentConvention = method.argumentConventions.first
    else {
        return
    }
    #expect(
        ObjectIdentifier(actualArgumentType) == ObjectIdentifier(argumentType),
        sourceLocation: sourceLocation
    )
    #expect(
        ObjectIdentifier(method.returnType) == ObjectIdentifier(returnType),
        sourceLocation: sourceLocation
    )
    #expect(argumentConvention == .concrete, sourceLocation: sourceLocation)
    #expect(method.returnConvention == .concrete, sourceLocation: sourceLocation)
    #expect(
        method.argumentAssociatedTypeUses == [.associatedType(named: "Element")],
        sourceLocation: sourceLocation
    )
    #expect(
        method.returnAssociatedTypeUse == .associatedType(named: "Element"),
        sourceLocation: sourceLocation
    )
}

private func assertDependentDictionary<Value>(
    _ method: RuntimeMethod,
    type: Value.Type,
    associatedTypeNames: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(method.argumentTypes.count == 1, sourceLocation: sourceLocation)
    #expect(
        method.argumentTypes.first.map(ObjectIdentifier.init) == ObjectIdentifier(type),
        sourceLocation: sourceLocation
    )
    #expect(
        ObjectIdentifier(method.returnType) == ObjectIdentifier(type),
        sourceLocation: sourceLocation
    )
    #expect(method.argumentConventions == [.concrete], sourceLocation: sourceLocation)
    #expect(method.returnConvention == .concrete, sourceLocation: sourceLocation)
    #expect(
        method.argumentAssociatedTypeUses.map(\.names) == [associatedTypeNames],
        sourceLocation: sourceLocation
    )
    #expect(
        method.returnAssociatedTypeUse.names == associatedTypeNames,
        sourceLocation: sourceLocation
    )
}

private func expectRequirementMismatch(
    at requirementIndex: Int,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () throws -> Void
) {
    expectStubError(operation, sourceLocation: sourceLocation) { error in
        guard case .requirementMismatch(_, let actualIndex, let expected, let actual) = error else {
            return false
        }
        return actualIndex == requirementIndex
            && expected.contains("[associated Element]")
            && actual.contains("[associated Element]") == false
    }
}

private func expectDictionaryRequirementMismatch(
    at requirementIndex: Int,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () throws -> Void
) {
    expectStubError(operation, sourceLocation: sourceLocation) { error in
        guard case .requirementMismatch(_, let actualIndex, let expected, let actual) = error else {
            return false
        }
        return actualIndex == requirementIndex
            && expected.contains("associated Dictionary value Value")
            && actual.contains("associated Dictionary key Key")
    }
}
