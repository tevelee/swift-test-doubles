import Foundation

final class StubPayload {
    let resources: StubResources

    init(resources: StubResources) {
        self.resources = resources
    }
}

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

/// Owns every runtime object used by fabricated protocol-conformance graphs.
final class StubResources: @unchecked Sendable {
    private var registryKeys: [UnsafeRawPointer] = []
    private var allocations: [UnsafeMutableRawPointer] = []
    private let trampolineArena: TrampolineFactory.Arena? = .init()
    private var lastTrampolineRequirementIndex: Int?
    private var typedWitnessAdapters: [TypedWitnessAdapter] = []

    func own(_ allocation: UnsafeMutableRawPointer) {
        allocations.append(allocation)
    }

    func register(
        _ target: FabricatedInvocationTarget,
        for registryKey: UnsafeRawPointer
    ) {
        FabricatedInvocationRegistry.register(target, for: registryKey)
        registryKeys.append(registryKey)
    }

    func makeTrampoline(
        kind: TrampolineFactory.Kind,
        slot: Int,
        context: UnsafeRawPointer
    ) -> UnsafeRawPointer? {
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
        guard trampolineArena?.publish() == true else {
            throw StubError.trampolineAllocationFailed(
                requirementIndex: lastTrampolineRequirementIndex ?? 0
            )
        }
    }

    deinit {
        for registryKey in registryKeys {
            FabricatedInvocationRegistry.remove(for: registryKey)
        }
        trampolineArena?.destroy()
        // Generic metadata caches retain witness-table identity without
        // retaining StubResources. Reusing one of these allocations could
        // therefore leave a cache key pointing at unrelated descriptor bytes.
        FabricatedWitnessAllocationArena.shared.retain(allocations)
    }
}

struct FabricatedWitnessTables {
    /// Root tables in canonical existential-metadata order.
    let roots: [UnsafeMutableRawPointer]
    let resources: StubResources
}
