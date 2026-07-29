import Foundation
import InternalRuntimeContract
import TestDoublesRuntimeMetadata

/// Couples a fabricated witness table with an opaque semantic endpoint and
/// precomputed ABI method plans. No public test-double type participates in
/// this runtime registry.
package final class RuntimeFabricatedInvocation: @unchecked Sendable {
    package let endpoint: any RuntimeInvocationEndpoint
    package let forwarder: (any RuntimeForwarding)?
    private let methods: [PreparedRuntimeMethod]

    package init(
        endpoint: any RuntimeInvocationEndpoint,
        methodsByIndex: [Int: MethodDescriptor],
        forwarder: (any RuntimeForwarding)? = nil
    ) {
        self.endpoint = endpoint
        self.forwarder = forwarder
        methods = (0 ..< methodsByIndex.count).map { index in
            guard let method = methodsByIndex[index] else {
                preconditionFailure(
                    "[TestDoubles] Fabricated runtime method indices must be dense."
                )
            }
            return PreparedRuntimeMethod(method)
        }
    }

    package func method(at index: Int) -> PreparedRuntimeMethod? {
        guard methods.indices.contains(index) else { return nil }
        return methods[index]
    }
}

/// Owns one process-global invocation-registry entry. Explicit cancellation
/// lets ``FabricatedRuntimeResources`` remove entries before destroying its
/// trampoline arena; `deinit` is the fallback for other failure paths.
package final class FabricatedInvocationRegistration: @unchecked Sendable {
    private let key: UnsafeRawPointer
    private let identifier: UInt64
    private let lock = NSLock()
    private var isActive = true

    fileprivate init(
        key: UnsafeRawPointer,
        identifier: UInt64
    ) {
        self.key = key
        self.identifier = identifier
    }

    package func cancel() {
        let shouldRemove = lock.withLock {
            guard isActive else { return false }
            isActive = false
            return true
        }
        guard shouldRemove else { return }
        FabricatedInvocationRegistry.remove(
            for: key,
            identifier: identifier
        )
    }

    deinit {
        cancel()
    }
}

/// Maps each fabricated witness table's stable context key to its invocation.
package enum FabricatedInvocationRegistry {
    private struct Entry {
        let identifier: UInt64
        let invocation: RuntimeFabricatedInvocation
    }

    private final class Shard: @unchecked Sendable {
        let lock = NSLock()
        var storage: [UnsafeRawPointer: Entry] = [:]
        var nextIdentifier: UInt64 = 0
    }

    private static let shards = (0 ..< 16).map { _ in Shard() }

    package static func register(
        _ invocation: RuntimeFabricatedInvocation,
        for key: UnsafeRawPointer
    ) -> FabricatedInvocationRegistration {
        let shard = shard(for: key)
        let identifier = shard.lock.withLock {
            precondition(
                shard.storage[key] == nil,
                "[TestDoubles] A fabricated witness table was registered more than once."
            )
            let identifier = shard.nextIdentifier
            let (successor, overflow) =
                shard.nextIdentifier.addingReportingOverflow(1)
            precondition(
                overflow == false,
                "[TestDoubles] Fabricated invocation registration identity overflowed."
            )
            shard.nextIdentifier = successor
            shard.storage[key] = Entry(
                identifier: identifier,
                invocation: invocation
            )
            return identifier
        }
        return FabricatedInvocationRegistration(
            key: key,
            identifier: identifier
        )
    }

    @inline(__always)
    package static func resolveOptional(
        _ key: UnsafeRawPointer
    ) -> RuntimeFabricatedInvocation? {
        let shard = shard(for: key)
        return shard.lock.withLock {
            shard.storage[key]?.invocation
        }
    }

    fileprivate static func remove(
        for key: UnsafeRawPointer,
        identifier: UInt64
    ) {
        let shard = shard(for: key)
        shard.lock.withLock {
            guard shard.storage[key]?.identifier == identifier else { return }
            shard.storage.removeValue(forKey: key)
        }
    }

    @inline(__always)
    private static func shard(for key: UnsafeRawPointer) -> Shard {
        // Veneer/context keys are at least word-aligned; discard those
        // invariant low bits before selecting a power-of-two shard.
        let address = UInt(bitPattern: key) >> 3
        return shards[Int(address & UInt(shards.count - 1))]
    }
}
