import Foundation

/// Keeps fabricated conformance descriptors and witness tables at stable
/// addresses for as long as Swift's generic-metadata caches may reference them.
private final class FabricatedWitnessAllocationArena: @unchecked Sendable {
    static let shared = FabricatedWitnessAllocationArena()

    private let lock = NSLock()
    private var allocations: [UnsafeMutableRawPointer] = []

    func retain(_ allocations: [UnsafeMutableRawPointer]) {
        lock.lock()
        self.allocations.append(contentsOf: allocations)
        lock.unlock()
    }
}

enum FabricatedWitnessAllocationDisposition: Equatable, Sendable {
    case deallocatedAfterFailedConstruction
    case retainedForProcessLifetime
}

enum FabricatedResourceConstructionPhase: Equatable, Sendable {
    case building
    case published
    case committed
}

/// Owns every runtime object used by fabricated protocol-conformance graphs.
final class StubResources: @unchecked Sendable {
    private var invocationRegistrations: [FabricatedInvocationRegistration] = []
    private var allocations: [UnsafeMutableRawPointer] = []
    private let trampolineArena: TrampolineFactory.Arena? = .init()
    private var lastTrampolineRequirementIndex: Int?
    private var typedWitnessAdapters: [TypedWitnessAdapter] = []
    private let witnessLifetimeObserver: (@Sendable (FabricatedWitnessAllocationDisposition) -> Void)?
    private(set) var constructionPhase = FabricatedResourceConstructionPhase.building

    init(
        witnessLifetimeObserver: (
            @Sendable (FabricatedWitnessAllocationDisposition) -> Void
        )? = nil
    ) {
        self.witnessLifetimeObserver = witnessLifetimeObserver
    }

    func own(_ allocation: UnsafeMutableRawPointer) {
        requireBuilding()
        allocations.append(allocation)
    }

    func register(
        _ target: FabricatedInvocationTarget,
        for registryKey: UnsafeRawPointer
    ) {
        requirePublished()
        invocationRegistrations.append(
            FabricatedInvocationRegistry.register(
                target,
                for: registryKey
            )
        )
    }

    func makeTrampoline(
        kind: TrampolineFactory.Kind,
        slot: Int,
        context: UnsafeRawPointer
    ) -> UnsafeRawPointer? {
        requireBuilding()
        guard
            let trampoline = trampolineArena?.make(
                kind: kind,
                slot: slot,
                context: context
            )
        else {
            return nil
        }
        lastTrampolineRequirementIndex = slot
        return trampoline
    }

    func makeTypedTrampoline(
        factory: TypedWitnessAdapterFactory,
        recorder: StubRecorder,
        method: MethodDescriptor
    ) -> UnsafeRawPointer? {
        requireBuilding()
        let adapter = factory.make(recorder, method)
        guard
            let trampoline = trampolineArena?.makeTyped(
                target: adapter.target,
                invocation: adapter.invocation,
                invocationArgumentIndex: adapter.invocationArgumentIndex
            )
        else {
            return nil
        }
        typedWitnessAdapters.append(adapter)
        lastTrampolineRequirementIndex = method.index
        return trampoline
    }

    func publishTrampolines() throws {
        requireBuilding()
        guard trampolineArena?.publish() == true else {
            throw StubError.trampolineAllocationFailed(
                requirementIndex: lastTrampolineRequirementIndex ?? 0
            )
        }
        constructionPhase = .published
    }

    /// Marks the fabricated witness identities as observable by generated
    /// existentials. Their addresses must remain stable for the rest of the
    /// process because Swift's generic-metadata caches may retain those keys.
    func commitWitnessIdentityLifetime() {
        requirePublished()
        constructionPhase = .committed
    }

    deinit {
        // Stop new calls from resolving these targets before their executable
        // trampoline pages and retained typed-adapter state are released.
        invocationRegistrations.forEach { $0.cancel() }
        invocationRegistrations.removeAll()
        trampolineArena?.destroy()
        switch constructionPhase {
            case .building, .published:
                // No fabricated existential escaped, so these identities could
                // not have entered a generic-metadata cache.
                allocations.forEach { $0.deallocate() }
                witnessLifetimeObserver?(.deallocatedAfterFailedConstruction)
            case .committed:
                // Generic metadata caches retain witness-table identity without
                // retaining StubResources. Reusing one of these allocations
                // could leave a cache key pointing at unrelated descriptor bytes.
                FabricatedWitnessAllocationArena.shared.retain(allocations)
                witnessLifetimeObserver?(.retainedForProcessLifetime)
        }
    }

    private func requireBuilding() {
        precondition(
            constructionPhase == .building,
            "[TestDoubles] Fabricated runtime resources can only allocate and build trampolines before publication."
        )
    }

    private func requirePublished() {
        precondition(
            constructionPhase == .published,
            "[TestDoubles] Fabricated runtime resources must publish trampolines exactly once before registration or commit."
        )
    }
}

struct FabricatedWitnessTables {
    /// Root tables in canonical existential-metadata order.
    let roots: [UnsafeMutableRawPointer]
    let resources: StubResources

    func makeStorage<P>(
        representation: StubExistentialRepresentation,
        payload: AnyObject
    ) throws -> FabricatedExistentialStorage<P> {
        let storage = try FabricatedExistentialStorage<P>(
            witnessTables: roots,
            representation: representation,
            payload: payload
        )
        resources.commitWitnessIdentityLifetime()
        return storage
    }
}
