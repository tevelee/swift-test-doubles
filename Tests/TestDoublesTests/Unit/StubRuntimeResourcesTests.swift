import Foundation
import Testing
@testable import TestDoubles

private final class WitnessAllocationLifetimeSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDispositions: [FabricatedWitnessAllocationDisposition] = []

    var observer: @Sendable (FabricatedWitnessAllocationDisposition) -> Void {
        { [self] disposition in record(disposition) }
    }

    var dispositions: [FabricatedWitnessAllocationDisposition] {
        lock.withLock { recordedDispositions }
    }

    private func record(_ disposition: FabricatedWitnessAllocationDisposition) {
        lock.withLock {
            recordedDispositions.append(disposition)
        }
    }
}

struct StubRuntimeResourcesTests {
    @Test func failedConstructionDeallocatesWitnessIdentities() {
        let spy = WitnessAllocationLifetimeSpy()

        releaseResources(committed: false, observer: spy.observer)

        #expect(spy.dispositions == [.deallocatedAfterFailedConstruction])
    }

    @Test func successfulConstructionRetainsWitnessIdentitiesForTheProcess() {
        let spy = WitnessAllocationLifetimeSpy()

        releaseResources(committed: true, observer: spy.observer)

        #expect(spy.dispositions == [.retainedForProcessLifetime])
    }

    @Test func resourceDestructionRemovesInvocationRegistrations() {
        let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { key.deallocate() }
        let recorder = StubRecorder(methods: [])

        do {
            let resources = StubResources()
            resources.register(.stub(recorder), for: UnsafeRawPointer(key))
            #expect(FabricatedInvocationRegistry.resolveOptional(key) != nil)
        }

        #expect(FabricatedInvocationRegistry.resolveOptional(key) == nil)
    }

    private func releaseResources(
        committed: Bool,
        observer: @escaping @Sendable (FabricatedWitnessAllocationDisposition) -> Void
    ) {
        let resources = StubResources(witnessLifetimeObserver: observer)
        resources.own(.allocate(byteCount: 1, alignment: 1))
        if committed {
            resources.commitWitnessIdentityLifetime()
        }
    }
}
