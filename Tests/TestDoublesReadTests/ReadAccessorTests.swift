import TestDoublesReadFixtures
import Testing
@testable import TestDoubles

private final class WeakReadReference: @unchecked Sendable {
    weak var value: ReadLifetimeReference?

    init(_ value: ReadLifetimeReference?) {
        self.value = value
    }
}

private struct ReadAbortFailure: Error {}

@Suite struct ReadAccessorTests {
    @Test func concretePropertyAndSubscriptDispatchThroughReadDescriptors() throws {
        _ = LinkedConcreteReadAccessorProbe()
        let stub = try Stub<any ConcreteReadAccessorProbe>()
        stub.when { $0.integer }.thenReturn(42)
        stub.when { $0.text }.thenReturn("forty-two")
        let dictionaryPlaceholder = ["placeholder": -1]
        stub.when(returning: dictionaryPlaceholder) { $0.dictionary }
            .thenReturn(["answer": 42])
        stub.when { $0[any()] }.then { (index: Int) in index * 2 }

        let probe: any ConcreteReadAccessorProbe = stub()
        #expect(probe.integer == 42)
        #expect(probe.text == "forty-two")
        #expect(probe.dictionary == ["answer": 42])
        #expect(probe[21] == 42)

        stub.verify(.exactly(1)) { $0.integer }
        stub.verify(.exactly(1)) { $0.text }
        stub.verify(.exactly(1), returning: dictionaryPlaceholder) {
            $0.dictionary
        }
        stub.verify(.exactly(1)) { $0[equal(21)] }
    }

    @Test func associatedResultUsesBorrowedIndirectStorage() throws {
        _ = LinkedAssociatedReadAccessorProbe()
        let stub = try Stub<any AssociatedReadAccessorProbe<Int>>()
        stub.when { $0.value }.thenReturn(41)
        stub.when { $0[any()] }.then { (index: Int) in index + 1 }

        let probe: any AssociatedReadAccessorProbe<Int> = stub()
        #expect(probe.value == 41)
        #expect(probe[41] == 42)
        stub.verify { $0.value }
        stub.verify { $0[equal(41)] }

        let value = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(value.returnConvention == .associatedType(name: "Value"))
        guard case .indirect = value.returnLayout else {
            Issue.record("Associated read result should use formal indirect storage")
            return
        }
    }

    @Test func explicitReadRequirementNeedsNoLinkedConformer() throws {
        let stub = try Stub<any ExplicitReadAccessorProbe>(
            .getter(Int.self)
        )
        stub.when { $0.value }.thenReturn(42)

        let probe: any ExplicitReadAccessorProbe = stub()
        #expect(probe.value == 42)
        stub.verify { $0.value }
    }

    @Test func readResultRemainsAliveForBorrowAndReleasesAfterUse() throws {
        _ = LinkedReadLifetimeProbe()
        let stub = try Stub<any ReadLifetimeProbe>()
        let weakReference = WeakReadReference(nil)
        stub.when(returning: ReadLifetimeValue(reference: ReadLifetimeReference(value: -1))) {
            $0.value
        }.then { () -> ReadLifetimeValue in
            let reference = ReadLifetimeReference(value: 42)
            weakReference.value = reference
            return ReadLifetimeValue(reference: reference)
        }
        let probe: any ReadLifetimeProbe = stub()

        #expect(consumeReadLifetimeValue(probe) == 42)
        #expect(weakReference.value == nil)
    }

    @Test func readResultReleasesExactlyOnceAfterAbort() throws {
        _ = LinkedReadLifetimeProbe()
        let stub = try Stub<any ReadLifetimeProbe>()
        let weakReference = WeakReadReference(nil)
        stub.when(returning: ReadLifetimeValue(reference: ReadLifetimeReference(value: -1))) {
            $0.value
        }.then { () -> ReadLifetimeValue in
            let reference = ReadLifetimeReference(value: 42)
            weakReference.value = reference
            return ReadLifetimeValue(reference: reference)
        }
        let probe: any ReadLifetimeProbe = stub()

        #expect(throws: ReadAbortFailure.self) {
            try abortReadLifetimeValue(probe.value)
        }
        #expect(weakReference.value == nil)
    }

    @Test func readRequirementMapsOneWitnessToOneGetterDispatch() throws {
        let layout = try Stub<any ConcreteReadAccessorProbe>.extractProtocolLayout()
        let node = try #require(layout.nodes.first)

        #expect(node.callableRequirements.map(\.witnessIndex) == [0, 1, 2, 3])
        #expect(
            node.callableRequirements.map(\.kind)
                == [.getter, .getter, .getter, .getter]
        )
        #expect(
            node.readCoroutineRequirements.map(\.witnessIndex)
                == [0, 1, 2, 3]
        )
        #expect(
            node.readCoroutineRequirements.map(\.recorderDispatchIndex)
                == [0, 1, 2, 3]
        )
        #expect(node.modifyCoroutineRequirements.isEmpty)
    }

    @Test func fabricatedWitnessContainsYieldOnce2Descriptor() throws {
        let stub = try Stub<any ExplicitReadAccessorProbe>(
            .getter(Int.self)
        )
        var probe: any ExplicitReadAccessorProbe = stub()
        let wordSize = MemoryLayout<UInt>.size
        let witnessAddress = withUnsafePointer(to: &probe) { pointer in
            UnsafeRawPointer(pointer).load(
                fromByteOffset: 4 * wordSize,
                as: UInt.self
            )
        }
        let witnessTable = try #require(
            UnsafeRawPointer(bitPattern: witnessAddress)
        )
        let descriptor = (witnessTable + wordSize).load(
            as: UnsafeRawPointer.self
        )
        let relativeEntry = descriptor.load(as: Int32.self)
        let frameSize = descriptor.load(fromByteOffset: 4, as: UInt32.self)
        let mallocTypeID = descriptor.load(fromByteOffset: 8, as: UInt64.self)
        let entry = descriptor + Int(relativeEntry)

        #expect(relativeEntry != 0)
        #expect(frameSize == 16)
        #expect(mallocTypeID == 0)
        #expect(entry != descriptor)
    }
}

@inline(never)
private func consumeReadLifetimeValue(
    _ probe: any ReadLifetimeProbe
) -> Int {
    probe.value.reference.value
}

@inline(never)
private func abortReadLifetimeValue(
    _ value: borrowing ReadLifetimeValue
) throws(ReadAbortFailure) -> Never {
    #expect(value.reference.value == 42)
    throw ReadAbortFailure()
}
