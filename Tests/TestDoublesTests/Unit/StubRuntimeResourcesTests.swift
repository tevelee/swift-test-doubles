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
    @Test func failedConstructionDeallocatesWitnessIdentities() throws {
        let spy = WitnessAllocationLifetimeSpy()

        try releaseResources(phase: .building, observer: spy.observer)

        #expect(spy.dispositions == [.deallocatedAfterFailedConstruction])
    }

    @Test func publishedConstructionStillDeallocatesWitnessIdentities() throws {
        let spy = WitnessAllocationLifetimeSpy()

        try releaseResources(phase: .published, observer: spy.observer)

        #expect(spy.dispositions == [.deallocatedAfterFailedConstruction])
    }

    @Test func successfulConstructionRetainsWitnessIdentitiesForTheProcess() throws {
        let spy = WitnessAllocationLifetimeSpy()

        try releaseResources(phase: .committed, observer: spy.observer)

        #expect(spy.dispositions == [.retainedForProcessLifetime])
    }

    @Test func constructionPhasesAdvanceOnlyAtPublicationAndCommit() throws {
        let resources = StubResources()

        #expect(resources.constructionPhase == .building)
        try resources.publishTrampolines()
        #expect(resources.constructionPhase == .published)
        resources.commitWitnessIdentityLifetime()
        #expect(resources.constructionPhase == .committed)
    }

    @Test func resourceDestructionRemovesInvocationRegistrations() throws {
        let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { key.deallocate() }
        let recorder = StubRecorder(methods: [])

        do {
            let resources = StubResources()
            try resources.publishTrampolines()
            resources.register(
                .stub(
                    FabricatedStubInvocation(
                        recorder: recorder,
                        methodsByIndex: [:],
                        forwarder: nil
                    )),
                for: UnsafeRawPointer(key)
            )
            #expect(FabricatedInvocationRegistry.resolveOptional(key) != nil)
        }

        #expect(FabricatedInvocationRegistry.resolveOptional(key) == nil)
    }

    @Test func registrationScopeOwnsRegistryCleanup() {
        let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { key.deallocate() }
        let recorder = StubRecorder(methods: [])

        do {
            let registration = FabricatedInvocationRegistry.register(
                .stub(
                    FabricatedStubInvocation(
                        recorder: recorder,
                        methodsByIndex: [:],
                        forwarder: nil
                    )),
                for: UnsafeRawPointer(key)
            )
            #expect(FabricatedInvocationRegistry.resolveOptional(key) != nil)
            withExtendedLifetime(registration) {}
        }

        #expect(FabricatedInvocationRegistry.resolveOptional(key) == nil)
    }

    private func releaseResources(
        phase: FabricatedResourceConstructionPhase,
        observer: @escaping @Sendable (FabricatedWitnessAllocationDisposition) -> Void
    ) throws {
        let resources = StubResources(witnessLifetimeObserver: observer)
        resources.own(.allocate(byteCount: 1, alignment: 1))
        switch phase {
            case .building:
                break
            case .published:
                try resources.publishTrampolines()
            case .committed:
                try resources.publishTrampolines()
                resources.commitWitnessIdentityLifetime()
        }
    }
}
