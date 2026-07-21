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

        #if compiler(>=6.4)
            #expect(
                node.callableRequirements.map(\.witnessIndex) == [1, 3, 5, 7]
            )
        #else
            #expect(
                node.callableRequirements.map(\.witnessIndex) == [0, 1, 2, 3]
            )
        #endif
        #expect(
            node.callableRequirements.map(\.kind)
                == [.getter, .getter, .getter, .getter]
        )
        #if compiler(>=6.4)
            #expect(
                node.readCoroutineRequirements.map(\.witnessIndex)
                    == [0, 1, 2, 3, 4, 5, 6, 7]
            )
            #expect(
                node.readCoroutineRequirements.map(\.recorderDispatchIndex)
                    == [0, 0, 1, 1, 2, 2, 3, 3]
            )
            #expect(
                node.readCoroutineRequirements.map(\.abi)
                    == [
                        .yieldOnce, .yieldOnce2,
                        .yieldOnce, .yieldOnce2,
                        .yieldOnce, .yieldOnce2,
                        .yieldOnce, .yieldOnce2
                    ]
            )
        #else
            #expect(
                node.readCoroutineRequirements.map(\.witnessIndex)
                    == [0, 1, 2, 3]
            )
            #expect(
                node.readCoroutineRequirements.map(\.recorderDispatchIndex)
                    == [0, 1, 2, 3]
            )
            #expect(
                node.readCoroutineRequirements.map(\.abi)
                    == [.yieldOnce2, .yieldOnce2, .yieldOnce2, .yieldOnce2]
            )
        #endif
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
        #if compiler(>=6.4)
            #expect((witnessTable + wordSize).load(as: UInt.self) == 0)
            let readWitnessIndex = 1
        #else
            let readWitnessIndex = 0
        #endif
        let descriptor = (witnessTable + (1 + readWitnessIndex) * wordSize).load(
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

    #if compiler(>=6.4)
        @Test func spyFailsClosedForPairedReadWitnesses() {
            let trace = ReadForwardingTrace()

            do {
                _ = try Spy<any ConcreteReadAccessorProbe>(
                    forwardingTo: ForwardingConcreteReadAccessorProbe(trace: trace)
                )
                Issue.record("Expected paired Swift 6.4 read witnesses to fail closed")
            } catch StubError.unsupportedProtocolShape(_, let reason) {
                #expect(reason.contains("paired legacy read and yielding-borrow"))
            } catch {
                Issue.record("Unexpected construction error: \(error)")
            }
        }
    #else
        @Test func spyForwardsConcreteReadPropertiesAndSubscripts() throws {
            let trace = ReadForwardingTrace()
            let spy = try Spy<any ConcreteReadAccessorProbe>(
                forwardingTo: ForwardingConcreteReadAccessorProbe(trace: trace)
            )
            let probe: any ConcreteReadAccessorProbe = spy()

            #expect(probe.integer == 7)
            #expect(probe.text == "forwarded")
            #expect(probe.dictionary == ["forwarded": 42])
            #expect(probe[21] == 42)
            #expect(
                trace.events
                    == [
                        "integer.begin", "integer.end",
                        "text.begin", "text.end",
                        "dictionary.begin", "dictionary.end",
                        "subscript.21.begin", "subscript.21.end"
                    ]
            )
            spy.verify { $0.integer }
            spy.verify { $0.text }
            spy.verify(returning: ["placeholder": -1]) { $0.dictionary }
            spy.verify { $0[equal(21)] }
        }

        @Test func configuredSpyReadOverrideWinsWithoutEnteringTarget() throws {
            let trace = ReadForwardingTrace()
            let spy = try Spy<any ConcreteReadAccessorProbe>(
                forwardingTo: ForwardingConcreteReadAccessorProbe(trace: trace)
            )
            spy.when { $0.integer }.thenReturn(42)
            let probe: any ConcreteReadAccessorProbe = spy()

            #expect(probe.integer == 42)
            #expect(trace.events.isEmpty)
            spy.verify { $0.integer }
        }

        @Test func spyForwardsFormallyIndirectAssociatedReadResults() throws {
            let trace = ReadForwardingTrace()
            let spy = try Spy<any AssociatedReadAccessorProbe<Int>>(
                forwardingTo: ForwardingAssociatedReadAccessorProbe(trace: trace)
            )
            let probe: any AssociatedReadAccessorProbe<Int> = spy()

            #expect(probe.value == 41)
            #expect(probe[41] == 42)
            #expect(
                trace.events
                    == [
                        "associated.value.begin", "associated.value.end",
                        "associated.subscript.41.begin",
                        "associated.subscript.41.end"
                    ]
            )
            spy.verify { $0.value }
            spy.verify { $0[equal(41)] }
        }

        @Test func forwardedReadRetainsYieldedValueUntilNormalResume() throws {
            let trace = ReadForwardingTrace()
            let spy = try Spy<any ReadLifetimeProbe>(
                forwardingTo: ForwardingReadLifetimeProbe(trace: trace)
            )
            let probe: any ReadLifetimeProbe = spy()

            #expect(consumeReadLifetimeValue(probe) == 42)
            #expect(trace.events == ["lifetime.begin", "lifetime.end"])
            #expect(trace.borrowedReference == nil)
            spy.verify(
                returning: ReadLifetimeValue(
                    reference: ReadLifetimeReference(value: -1)
                )
            ) { $0.value }
        }

        @Test func forwardedReadResumesTargetExactlyOnceAfterAbort() throws {
            let trace = ReadForwardingTrace()
            let spy = try Spy<any ReadLifetimeProbe>(
                forwardingTo: ForwardingReadLifetimeProbe(trace: trace)
            )
            let probe: any ReadLifetimeProbe = spy()

            #expect(throws: ReadForwardingAbortError.self) {
                try probe.value.reference.abortBorrow()
            }
            #expect(trace.events == ["lifetime.begin", "lifetime.end"])
            #expect(trace.borrowedReference == nil)
            spy.verify(
                returning: ReadLifetimeValue(
                    reference: ReadLifetimeReference(value: -1)
                )
            ) { $0.value }
        }
    #endif
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
