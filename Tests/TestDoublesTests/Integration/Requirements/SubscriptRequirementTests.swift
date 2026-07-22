import Foundation
import Testing
@testable import TestDoubles

private final class LockedHandledArguments: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (value: Int, index: Int, name: String)?

    var value: (value: Int, index: Int, name: String)? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(value: Int, index: Int, name: String) {
        lock.lock()
        storage = (value, index, name)
        lock.unlock()
    }
}

// Runtime-discovery fixtures must remain module-internal. Release whole-module
// optimization can otherwise remove private conformances before inspection.
protocol AutomaticGetOnlySubscriptProbe {
    subscript(_ index: Int) -> String { get }
}

struct LinkedAutomaticGetOnlySubscriptProbe: AutomaticGetOnlySubscriptProbe {
    subscript(index: Int) -> String { "\(index)" }
}

protocol ConcreteReadWriteSubscriptProbe {
    subscript(_ index: Int, named name: String) -> Int { get set }
}

struct LinkedConcreteReadWriteSubscriptProbe: ConcreteReadWriteSubscriptProbe {
    subscript(index: Int, named name: String) -> Int {
        get { index + name.count }
        set {}
    }
}

protocol AssociatedReadWriteSubscriptProbe<Value> {
    associatedtype Value
    subscript(_ key: String) -> Value? { get set }
}

struct LinkedAssociatedReadWriteSubscriptProbe: AssociatedReadWriteSubscriptProbe {
    subscript(key: String) -> Int? {
        get { key.count }
        set {}
    }
}

private protocol ExplicitNoLinkedSubscriptProbe {
    subscript(_ index: Int) -> String { get }
}

private protocol ExplicitNoLinkedReadWriteSubscriptProbe {
    subscript(_ index: Int, named name: String) -> Bool { get set }
}

typealias SubscriptFunctionValue = @Sendable (Int) -> Int
typealias SubscriptClosureValue = (Int) -> Int

protocol FunctionValuedPropertyProbe {
    var transform: SubscriptFunctionValue { get }
}

struct LinkedFunctionValuedPropertyProbe: FunctionValuedPropertyProbe {
    var transform: SubscriptFunctionValue { { $0 } }
}

private protocol FunctionValuedSubscriptProbe {
    subscript(_ offset: Int) -> SubscriptClosureValue { get }
}

@inline(never)
private func useLinkedGetOnlySubscript(
    _ value: any AutomaticGetOnlySubscriptProbe
) -> String {
    value[1]
}

@inline(never)
private func useLinkedConcreteReadWriteSubscript(
    _ value: any ConcreteReadWriteSubscriptProbe
) -> Int {
    value[1, named: "linked"]
}

@inline(never)
private func useLinkedAssociatedReadWriteSubscript(
    _ value: any AssociatedReadWriteSubscriptProbe<Int>
) -> Int? {
    value["linked"]
}

@Suite struct SubscriptRequirementTests {
    @Test func automaticGetOnlySubscriptRecordsHandlesAndVerifiesIndices() throws {
        #expect(useLinkedGetOnlySubscript(LinkedAutomaticGetOnlySubscriptProbe()) == "1")
        let stub = try Stub<any AutomaticGetOnlySubscriptProbe>()
        stub.when { $0[any()] }.then { (index: Int) in
            "value-\(index)"
        }

        let probe: any AutomaticGetOnlySubscriptProbe = stub()
        #expect(probe[7] == "value-7")
        stub.verify { $0[equal(7)] }

        let getter = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(getter.kind == .getter)
        #expect(getter.name == "subscript")
        #expect(getter.argumentTypes.count == 1)
        #expect(ObjectIdentifier(getter.argumentTypes[0]) == ObjectIdentifier(Int.self))
        #expect(getter.argumentConventions == [.concrete])
        #expect(getter.argumentOwnerships == [.borrowed])
        #expect(ObjectIdentifier(getter.returnType) == ObjectIdentifier(String.self))
        #expect(getter.signatureDescription.contains("indices:"))
    }

    @Test func explicitGetOnlySubscriptWorksWithoutLinkedConformer() throws {
        let stub = try Stub<any ExplicitNoLinkedSubscriptProbe>(
            .subscriptGetter(indexedBy: Int.self, returning: String.self)
        )
        stub.when { $0[equal(3)] }.thenReturn("three")

        let probe: any ExplicitNoLinkedSubscriptProbe = stub()
        #expect(probe[3] == "three")
        stub.verify { $0[equal(3)] }
    }

    @Test func concreteReadWriteSubscriptUsesValueFirstSetterABIOrder() throws {
        #expect(
            useLinkedConcreteReadWriteSubscript(LinkedConcreteReadWriteSubscriptProbe()) == 7
        )
        let stub = try Stub<any ConcreteReadWriteSubscriptProbe>()
        stub.when { $0[any(), named: any()] }.thenReturn(11)

        let handledArguments = LockedHandledArguments()
        stub.when {
            $0[equal(4), named: equal("four")] = equal(44)
        }.then { (value: Int, index: Int, name: String) in
            handledArguments.store(value: value, index: index, name: name)
        }

        var probe: any ConcreteReadWriteSubscriptProbe = stub()
        #expect(probe[2, named: "two"] == 11)
        probe[4, named: "four"] = 44
        #expect(handledArguments.value?.value == 44)
        #expect(handledArguments.value?.index == 4)
        #expect(handledArguments.value?.name == "four")
        stub.verify { $0[equal(4), named: equal("four")] = equal(44) }

        let setter = try #require(stub.recorder.runtimeMethod(for: 1))
        #expect(setter.kind == .setter)
        #expect(setter.argumentTypes.count == 3)
        #expect(ObjectIdentifier(setter.argumentTypes[0]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(setter.argumentTypes[1]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(setter.argumentTypes[2]) == ObjectIdentifier(String.self))
        #expect(setter.argumentConventions == [.concrete, .concrete, .concrete])
        #expect(setter.argumentOwnerships == [.owned, .borrowed, .borrowed])
        #expect(ObjectIdentifier(setter.returnType) == ObjectIdentifier(Void.self))
        #expect(setter.signatureDescription.contains("value:"))
        #expect(setter.signatureDescription.contains("indices:"))
    }

    @Test func explicitConcreteSubscriptSetterSupportsIndexParameterPacks() throws {
        let stub = try Stub<any ExplicitNoLinkedReadWriteSubscriptProbe>(
            .subscriptGetter(
                indexedBy: Int.self, String.self,
                returning: Bool.self
            ),
            .subscriptSetter(
                indexedBy: Int.self, String.self,
                assigning: Bool.self
            )
        )
        stub.when { $0[any(), named: any()] }.thenReturn(true)
        stub.when { $0[any(), named: any()] = any() }.thenDoNothing()

        var probe: any ExplicitNoLinkedReadWriteSubscriptProbe = stub()
        #expect(probe[1, named: "one"])
        probe[2, named: "two"] = false
        stub.verify { $0[equal(2), named: equal("two")] = equal(false) }
    }

    @Test func associatedOptionalSubscriptSupportsExplicitRequirementsAndCaptorOrder() throws {
        #expect(
            useLinkedAssociatedReadWriteSubscript(LinkedAssociatedReadWriteSubscriptProbe()) == 6
        )
        typealias ProbeStub = Stub<any AssociatedReadWriteSubscriptProbe<Int>>
        let key = ProbeStub.Requirement.Value.concrete(String.self)
        let optionalValue = ProbeStub.Requirement.Value.optionalAssociatedType(named: "Value")
        let stub = try ProbeStub(
            .subscriptGetter(
                indexedBy: key,
                returning: optionalValue
            ),
            .subscriptSetter(
                indexedBy: key,
                assigning: optionalValue
            )
        )
        stub.when { $0[equal("answer")] }.thenReturn(42)
        stub.when { $0[any()] = any() }.thenDoNothing()

        var probe: any AssociatedReadWriteSubscriptProbe<Int> = stub()
        #expect(probe["answer"] == 42)
        probe["answer"] = 43

        let valueCaptor = ArgumentCaptor<Int?>()
        let keyCaptor = ArgumentCaptor<String>()
        stub.verify { $0[keyCaptor.capture()] = valueCaptor.capture() }
        #expect(valueCaptor.values == [43])
        #expect(keyCaptor.values == ["answer"])

        let setter = try #require(stub.recorder.runtimeMethod(for: 1))
        #expect(
            setter.argumentConventions == [
                WitnessValueConvention.associatedType(name: "Value"),
                WitnessValueConvention.concrete
            ])
        #expect(
            setter.argumentOwnerships == [
                WitnessArgumentOwnership.owned,
                WitnessArgumentOwnership.borrowed
            ])
        #expect(
            setter.argumentDependencies == [
                WitnessValueDependency.associatedType(name: "Value"),
                WitnessValueDependency.independent
            ])
    }

    @Test func matcherOrderAppliesToSubscriptIndices() throws {
        #expect(useLinkedGetOnlySubscript(LinkedAutomaticGetOnlySubscriptProbe()) == "1")
        let stub = try Stub<any AutomaticGetOnlySubscriptProbe>()
        stub.when { $0[equal(7)] }.thenReturn("specific")
        stub.when { $0[any()] }.thenReturn("fallback")

        let probe: any AutomaticGetOnlySubscriptProbe = stub()
        #expect(probe[7] == "specific")
        #expect(probe[8] == "fallback")
    }

    @Test func multiIndexCompoundMutationPreservesSetterABIOrder() throws {
        #expect(
            useLinkedConcreteReadWriteSubscript(LinkedConcreteReadWriteSubscriptProbe()) == 7
        )
        let stub = try Stub<any ConcreteReadWriteSubscriptProbe>()
        stub.when { $0[equal(3), named: equal("three")] }.thenReturn(10)
        let handledArguments = LockedHandledArguments()
        stub.when { $0[any(), named: any()] = any() }.then {
            (value: Int, index: Int, name: String) in
            handledArguments.store(value: value, index: index, name: name)
        }
        var probe: any ConcreteReadWriteSubscriptProbe = stub()

        probe[3, named: "three"] += 5

        #expect(handledArguments.value?.value == 15)
        #expect(handledArguments.value?.index == 3)
        #expect(handledArguments.value?.name == "three")
        stub.verify { $0[equal(3), named: equal("three")] }
        stub.verify { $0[equal(3), named: equal("three")] = equal(15) }
        stub.verifyInOrder(mutating: {
            _ = $0[equal(3), named: equal("three")]
            $0[equal(3), named: equal("three")] = equal(15)
        })
    }

    @Test func typedAdapterSupportsFunctionValuedProperty() throws {
        _ = LinkedFunctionValuedPropertyProbe()
        let placeholder: SubscriptFunctionValue = { $0 }
        let adapter:
            @convention(thin) (
                Stub<any FunctionValuedPropertyProbe>.Invocation
            ) -> SubscriptFunctionValue = { invocation in
                invocation.call()
            }
        let stub = try Stub<any FunctionValuedPropertyProbe>(
            .getter(
                SubscriptFunctionValue.self,
                using: adapter
            )
        )
        stub.when(returning: placeholder) { $0.transform }.thenReturn { $0 + 1 }

        let probe: any FunctionValuedPropertyProbe = stub()
        #expect(probe.transform(41) == 42)
        stub.verify(returning: placeholder) { $0.transform }
    }

    @Test func typedAdapterSupportsFunctionValuedSubscript() throws {
        let placeholder: SubscriptFunctionValue = { $0 }
        let adapter:
            @convention(thin) (
                Int,
                Stub<any FunctionValuedSubscriptProbe>.Invocation
            ) -> SubscriptClosureValue = { offset, invocation in
                invocation.call(offset, returning: SubscriptClosureValue.self)
            }
        let stub = try Stub<any FunctionValuedSubscriptProbe>(
            .subscriptGetter(
                indexedBy: Int.self,
                returning: SubscriptClosureValue.self,
                using: adapter
            )
        )
        stub.when(returning: placeholder) { $0[any()] }.then { (offset: Int) in
            { $0 + offset }
        }

        let probe: any FunctionValuedSubscriptProbe = stub()
        #expect(probe[2](40) == 42)
        stub.verify(returning: placeholder) { $0[equal(2)] }
    }

    @Test func automaticallyDiscoveredFunctionValuedPropertyNeedsNoRequirements() throws {
        _ = LinkedFunctionValuedPropertyProbe()
        let placeholder: SubscriptFunctionValue = { $0 }
        let offset = 1
        let stub = try Stub<any FunctionValuedPropertyProbe>()
        stub.when(returning: placeholder) { $0.transform }
            .thenReturn { $0 + offset }

        let probe: any FunctionValuedPropertyProbe = stub()
        #expect(probe.transform(41) == 42)
        stub.verify(returning: placeholder) { $0.transform }
    }

    @Test func mandatoryModifySlotMapsToGetterAndSetterDispatch() throws {
        let layout = try Stub<any ConcreteReadWriteSubscriptProbe>.extractProtocolLayout()
        let node = try #require(layout.nodes.first)

        #expect(node.callableRequirements.map(\.witnessIndex) == [0, 1])
        #expect(node.callableRequirements.map(\.kind) == [.getter, .setter])
        #expect(node.modifyCoroutineRequirements.map(\.witnessIndex) == [2])
        #expect(node.modifyCoroutineRequirements.map(\.abi) == [.yieldOnce])
        #expect(node.modifyCoroutineRequirements.first?.getterDispatchIndex == 0)
        #expect(node.modifyCoroutineRequirements.first?.setterDispatchIndex == 1)
    }
}
