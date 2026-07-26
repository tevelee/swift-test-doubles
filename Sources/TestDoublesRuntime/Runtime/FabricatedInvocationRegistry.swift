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

/// Owns one process-global invocation-registry entry.
///
/// Explicit cancellation lets ``FabricatedRuntimeResources`` remove callable
/// registry entries before destroying its executable trampoline arena. The
/// fallback `deinit` cleanup keeps a registration scoped even when construction
/// exits through a new failure path.
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

    nonisolated(unsafe) private static var storage: [UnsafeRawPointer: Entry] = [:]
    nonisolated(unsafe) private static var nextIdentifier: UInt64 = 0
    private static let lock = NSLock()

    package static func register(
        _ invocation: RuntimeFabricatedInvocation,
        for key: UnsafeRawPointer
    ) -> FabricatedInvocationRegistration {
        let identifier = lock.withLock {
            precondition(
                storage[key] == nil,
                "[TestDoubles] A fabricated witness table was registered more than once."
            )
            let identifier = nextIdentifier
            let (successor, overflow) = nextIdentifier.addingReportingOverflow(1)
            precondition(
                overflow == false,
                "[TestDoubles] Fabricated invocation registration identity overflowed."
            )
            nextIdentifier = successor
            storage[key] = Entry(
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
        lock.lock()
        defer { lock.unlock() }
        return storage[key]?.invocation
    }

    fileprivate static func remove(
        for key: UnsafeRawPointer,
        identifier: UInt64
    ) {
        lock.withLock {
            guard storage[key]?.identifier == identifier else { return }
            storage.removeValue(forKey: key)
        }
    }
}
