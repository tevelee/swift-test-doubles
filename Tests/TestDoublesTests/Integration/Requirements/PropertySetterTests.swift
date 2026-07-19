import Foundation
import Testing
@testable import TestDoubles

private final class SetterReference {}

private struct LargeSetterValue {
    let reference: SetterReference
    let label: String
    let first: Int
    let second: Int
}

private struct MixedSetterValue {
    let reference: SetterReference
    let amount: Float
}

private struct ReferenceModifyValue {
    var reference: SetterReference?
    var count: Int
}

private enum SetterMutationError: Error {
    case stopped
}

protocol AutomaticSetterProbe {
    var integer: Int { get set }
}

private protocol ReferenceSetterProbe {
    var reference: SetterReference { get set }
}

private protocol LargeSetterProbe {
    var large: LargeSetterValue { get set }
}

private protocol MixedSetterProbe {
    var mixed: MixedSetterValue { get set }
}

private protocol ReferenceModifyProbe {
    var value: ReferenceModifyValue { get set }
}

struct LinkedAutomaticSetterProbe: AutomaticSetterProbe {
    var integer: Int {
        get { 0 }
        set {}
    }
}

private protocol ExplicitSetterProbe {
    var text: String { get set }
}

protocol InheritedSetterBaseProbe {
    var inheritedValue: Int { get set }
}

protocol InheritedSetterChildProbe: InheritedSetterBaseProbe {
    var childValue: String { get set }
}

struct LinkedInheritedSetterProbe: InheritedSetterChildProbe {
    var inheritedValue: Int {
        get { 0 }
        set {}
    }
    var childValue: String {
        get { "" }
        set {}
    }
}

protocol SetterCompositionA {
    var firstValue: Int { get set }
}

protocol SetterCompositionB {
    var secondValue: String { get set }
}

struct LinkedSetterCompositionA: SetterCompositionA {
    var firstValue: Int {
        get { 0 }
        set {}
    }
}

struct LinkedSetterCompositionB: SetterCompositionB {
    var secondValue: String {
        get { "" }
        set {}
    }
}

@inline(never)
private func useLinkedAutomaticSetter(_ value: any AutomaticSetterProbe) -> Int {
    value.integer
}

@inline(never)
private func useLinkedInheritedSetter(_ value: any InheritedSetterChildProbe) -> Int {
    value.inheritedValue
}

@inline(never)
private func useLinkedSetterCompositionA(_ value: any SetterCompositionA) -> Int {
    value.firstValue
}

@inline(never)
private func useLinkedSetterCompositionB(_ value: any SetterCompositionB) -> String {
    value.secondValue
}

private final class LockedSetterValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func clear() {
        lock.lock()
        storage = nil
        lock.unlock()
    }
}

@Suite struct PropertySetterTests {
    @Test func automaticSetterRecordsMatchesHandlesAndVerifies() throws {
        #expect(useLinkedAutomaticSetter(LinkedAutomaticSetterProbe()) == 0)
        let stub = try Stub<any AutomaticSetterProbe>()
        let received = LockedSetterValue<Int>()
        stub.when { $0.integer = any() }.then { (value: Int) in
            received.store(value)
        }

        var probe: any AutomaticSetterProbe = stub()
        probe.integer = 42

        #expect(received.value == 42)
        stub.verify(.exactly(1)) { $0.integer = equal(42) }

        let captor = ArgumentCaptor<Int>()
        stub.verify { $0.integer = captor.capture() }
        #expect(captor.values == [42])
    }

    @Test func explicitSetterUsesGetterThenSetterRequirementOrder() throws {
        let stub = try Stub<any ExplicitSetterProbe>(
            .getter(String.self),
            .setter(String.self)
        )
        stub.when { $0.text = matching(description: "prefix") { $0.hasPrefix("new") } }
            .thenDoNothing()

        var probe: any ExplicitSetterProbe = stub()
        probe.text = "new value"

        stub.verify { $0.text = "new value" }
    }

    @Test func setterDescriptorsPreserveOwnedValueAndVoidResult() throws {
        #expect(useLinkedAutomaticSetter(LinkedAutomaticSetterProbe()) == 0)
        let stub = try Stub<any AutomaticSetterProbe>()
        let integerSetter = try #require(stub.recorder.runtimeMethod(for: 1))

        #expect(integerSetter.kind == .setter)
        #expect(integerSetter.name == "integer")
        #expect(integerSetter.argumentTypes.count == 1)
        #expect(ObjectIdentifier(integerSetter.argumentTypes[0]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(integerSetter.returnType) == ObjectIdentifier(Void.self))
        #expect(integerSetter.isThrowing == false)
        #expect(integerSetter.isAsync == false)
    }

    @Test func inheritedSettersUseTheirDeclaringWitnessTables() throws {
        #expect(useLinkedInheritedSetter(LinkedInheritedSetterProbe()) == 0)
        let stub = try Stub<any InheritedSetterChildProbe>()
        stub.when { $0.inheritedValue = any() }.thenDoNothing()
        stub.when { $0.childValue = any() }.thenDoNothing()

        var probe: any InheritedSetterChildProbe = stub()
        probe.inheritedValue = 7
        probe.childValue = "child"

        stub.verify { $0.inheritedValue = 7 }
        stub.verify { $0.childValue = "child" }
    }

    @Test func composedSettersSupportAutomaticAndGroupedExplicitConstruction() throws {
        #expect(useLinkedSetterCompositionA(LinkedSetterCompositionA()) == 0)
        #expect(useLinkedSetterCompositionB(LinkedSetterCompositionB()) == "")
        let automatic = try Stub<any SetterCompositionA & SetterCompositionB>()
        automatic.when { $0.firstValue = any() }.thenDoNothing()
        automatic.when { $0.secondValue = any() }.thenDoNothing()

        var automaticProbe: any SetterCompositionA & SetterCompositionB = automatic()
        automaticProbe.firstValue = 1
        automaticProbe.secondValue = "two"
        automatic.verify { $0.firstValue = 1 }
        automatic.verify { $0.secondValue = "two" }

        let explicit = try Stub<any SetterCompositionA & SetterCompositionB>(
            requirementsByProtocol: .requirements(
                declaredBy: SetterCompositionB.self,
                .getter(String.self),
                .setter(String.self)
            ),
            .requirements(
                declaredBy: SetterCompositionA.self,
                .getter(Int.self),
                .setter(Int.self)
            )
        )
        explicit.when { $0.firstValue = 3 }.thenDoNothing()
        explicit.when { $0.secondValue = "four" }.thenDoNothing()

        var explicitProbe: any SetterCompositionA & SetterCompositionB = explicit()
        explicitProbe.firstValue = 3
        explicitProbe.secondValue = "four"
        explicit.verify { $0.firstValue = 3 }
        explicit.verify { $0.secondValue = "four" }
    }

    @Test func referenceSetterConsumesItsOwnedArgumentExactlyOnce() throws {
        let weakReference = try exerciseReferenceSetterLifetime()
        #expect(weakReference.value == nil)
    }

    @Test func indirectSetterConsumesItsOwnedArgumentExactlyOnce() throws {
        let weakReference = try exerciseLargeSetterLifetime()
        #expect(weakReference.value == nil)
    }

    @Test func mixedAggregateSetterConsumesItsOwnedArgumentExactlyOnce() throws {
        let weakReference = try exerciseMixedSetterLifetime()
        #expect(weakReference.value == nil)
    }

    @Test func compoundAssignmentUsesGetterThenWritesBackThroughSetter() throws {
        #expect(useLinkedAutomaticSetter(LinkedAutomaticSetterProbe()) == 0)
        let stub = try Stub<any AutomaticSetterProbe>()
        stub.when { $0.integer }.thenReturn(40)
        stub.when { $0.integer = any() }.thenDoNothing()
        var probe: any AutomaticSetterProbe = stub()

        probe.integer += 2

        stub.verify(.exactly(1)) { $0.integer }
        stub.verify(.exactly(1)) { $0.integer = equal(42) }
        stub.verifyInOrder(mutating: {
            _ = $0.integer
            $0.integer = equal(42)
        })
    }

    @Test func inoutMutationWritesBackThroughSetter() throws {
        #expect(useLinkedAutomaticSetter(LinkedAutomaticSetterProbe()) == 0)
        let stub = try Stub<any AutomaticSetterProbe>()
        stub.when { $0.integer }.thenReturn(8)
        stub.when { $0.integer = any() }.thenDoNothing()
        var probe: any AutomaticSetterProbe = stub()

        increment(&probe.integer)

        stub.verify { $0.integer }
        stub.verify { $0.integer = equal(9) }
    }

    @Test func thrownInoutMutationStillWritesBackBeforeUnwinding() throws {
        #expect(useLinkedAutomaticSetter(LinkedAutomaticSetterProbe()) == 0)
        let stub = try Stub<any AutomaticSetterProbe>()
        stub.when { $0.integer }.thenReturn(10)
        stub.when { $0.integer = any() }.thenDoNothing()
        var probe: any AutomaticSetterProbe = stub()

        do {
            try mutateThenThrow(&probe.integer)
            Issue.record("Expected the inout mutation to throw")
        } catch SetterMutationError.stopped {
            // The mutation made before the throw must still be written back.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        stub.verify { $0.integer }
        stub.verify { $0.integer = equal(15) }
    }

    @Test func explicitPropertySupportsInoutMutation() throws {
        let stub = try Stub<any ExplicitSetterProbe>(
            .getter(String.self),
            .setter(String.self)
        )
        stub.when { $0.text }.thenReturn("swift")
        stub.when { $0.text = any() }.thenDoNothing()
        var probe: any ExplicitSetterProbe = stub()

        appendExclamationMark(&probe.text)

        stub.verify { $0.text }
        stub.verify { $0.text = equal("swift!") }
    }

    @Test func modifyStorageReleasesReferenceContainingValueAfterWriteback() throws {
        let stub = try Stub<any ReferenceModifyProbe>(
            .getter(ReferenceModifyValue.self),
            .setter(ReferenceModifyValue.self)
        )
        let source = LockedSetterValue<ReferenceModifyValue>()
        var reference: SetterReference? = SetterReference()
        let weakReference = WeakReference(reference)
        source.store(ReferenceModifyValue(reference: reference, count: 1))
        stub.when { $0.value }.then { () -> ReferenceModifyValue in
            guard let value = source.value else {
                fatalError("Expected a source value")
            }
            return value
        }
        stub.when { $0.value = any() }.thenDoNothing()
        var probe: any ReferenceModifyProbe = stub()

        clearReferenceAndIncrement(&probe.value)
        source.clear()
        reference = nil

        #expect(weakReference.value == nil)
        stub.verify {
            $0.value = matching { value in
                value.reference == nil && value.count == 2
            }
        }
    }

    @Test func mandatoryModifySlotsContainCoroutineWitnesses() throws {
        let layout = try Stub<any AutomaticSetterProbe>.extractProtocolLayout()
        let node = try #require(layout.nodes.first)
        let stub = try Stub<any AutomaticSetterProbe>(
            .getter(Int.self),
            .setter(Int.self)
        )
        var probe: any AutomaticSetterProbe = stub()
        let wordSize = MemoryLayout<UInt>.size
        let witnessAddress = withUnsafePointer(to: &probe) { pointer in
            UnsafeRawPointer(pointer).load(
                fromByteOffset: 4 * wordSize,
                as: UInt.self
            )
        }
        let witnessTable = try #require(UnsafeRawPointer(bitPattern: witnessAddress))
        let entries = (0 ..< 3).map { index in
            UInt(
                bitPattern: (witnessTable + (1 + index) * wordSize)
                    .load(as: UnsafeRawPointer.self))
        }

        #expect(node.callableRequirements.map(\.witnessIndex) == [0, 1])
        #expect(node.modifyCoroutineRequirements.map(\.witnessIndex) == [2])
        #expect(node.modifyCoroutineRequirements.first?.getterDispatchIndex == 0)
        #expect(node.modifyCoroutineRequirements.first?.setterDispatchIndex == 1)
        #expect(entries.count == 3)
        #expect(entries[1] != 0)
        #expect(entries[2] != 0)
        #expect(entries[1] != entries[2])
    }
}

@inline(never)
private func increment(_ value: inout Int) {
    value += 1
}

@inline(never)
private func mutateThenThrow(_ value: inout Int) throws {
    value += 5
    throw SetterMutationError.stopped
}

@inline(never)
private func appendExclamationMark(_ value: inout String) {
    value.append("!")
}

@inline(never)
private func clearReferenceAndIncrement(_ value: inout ReferenceModifyValue) {
    #expect(value.reference != nil)
    value.reference = nil
    value.count += 1
}

private func exerciseReferenceSetterLifetime() throws -> WeakReference<SetterReference> {
    var stub: Stub<any ReferenceSetterProbe>? = try Stub(
        .getter(SetterReference.self),
        .setter(SetterReference.self)
    )
    var placeholder: SetterReference? = SetterReference()
    stub?.when { $0.reference = any(using: placeholder!) }.thenDoNothing()
    var probe: (any ReferenceSetterProbe)? = stub?()
    var assigned: SetterReference? = SetterReference()
    let weakReference = WeakReference(assigned)

    probe?.reference = assigned!
    assigned = nil
    placeholder = nil
    #expect(weakReference.value != nil)

    probe = nil
    stub = nil
    return weakReference
}

private func exerciseLargeSetterLifetime() throws -> WeakReference<SetterReference> {
    var stub: Stub<any LargeSetterProbe>? = try Stub(
        .getter(LargeSetterValue.self),
        .setter(LargeSetterValue.self)
    )
    var placeholderReference: SetterReference? = SetterReference()
    stub?.when {
        $0.large = any(
            using: LargeSetterValue(
                reference: placeholderReference!,
                label: "placeholder",
                first: 0,
                second: 0
            ))
    }.thenDoNothing()
    var probe: (any LargeSetterProbe)? = stub?()
    var assignedReference: SetterReference? = SetterReference()
    let weakReference = WeakReference(assignedReference)

    probe?.large = LargeSetterValue(
        reference: assignedReference!,
        label: "actual",
        first: 1,
        second: 2
    )
    assignedReference = nil
    placeholderReference = nil
    #expect(weakReference.value != nil)

    probe = nil
    stub = nil
    return weakReference
}

private func exerciseMixedSetterLifetime() throws -> WeakReference<SetterReference> {
    var stub: Stub<any MixedSetterProbe>? = try Stub(
        .getter(MixedSetterValue.self),
        .setter(MixedSetterValue.self)
    )
    var placeholderReference: SetterReference? = SetterReference()
    stub?.when {
        $0.mixed = any(
            using: MixedSetterValue(
                reference: placeholderReference!,
                amount: 0
            ))
    }.thenDoNothing()
    var probe: (any MixedSetterProbe)? = stub?()
    var assignedReference: SetterReference? = SetterReference()
    let weakReference = WeakReference(assignedReference)

    probe?.mixed = MixedSetterValue(
        reference: assignedReference!,
        amount: 2.5
    )
    assignedReference = nil
    placeholderReference = nil
    #expect(weakReference.value != nil)

    probe = nil
    stub = nil
    return weakReference
}
