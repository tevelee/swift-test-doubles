import Foundation

final class DummyInvocation: Sendable {
    struct Requirement: Sendable {
        let protocolName: String
        let witnessIndex: Int
        let kind: StubRequirementKind
    }

    private let typeDescription: String
    private let requirements: [Int: Requirement]

    init(
        typeDescription: String,
        requirements: [Int: Requirement]
    ) {
        self.typeDescription = typeDescription
        self.requirements = requirements
    }

    func reject(slot: Int) -> Never {
        fatalError(rejectionMessage(slot: slot))
    }

    func rejectionMessage(slot: Int) -> String {
        let requirementDescription =
            requirements[slot].map {
                "\($0.protocolName) \($0.kind.rawValue) requirement at witness index \($0.witnessIndex)"
            } ?? "unknown requirement at dispatch slot \(slot)"
        return "[TestDoubles] Dummy<\(typeDescription)> was invoked through \(requirementDescription). "
            + "A dummy may only be passed to code paths that do not use it. If this invocation is "
            + "expected, replace the dummy with `Stub`, `ManualStub`, or a hand-written fake."
    }
}

enum FabricatedInvocationTarget: Sendable {
    case stub(StubRecorder)
    case spy(StubRecorder, any ProtocolForwarding)
    case dummy(DummyInvocation)

    func recorderOrReject(slot: Int) -> StubRecorder {
        switch self {
            case .stub(let recorder):
                return recorder
            case .spy(let recorder, _):
                return recorder
            case .dummy(let invocation):
                invocation.reject(slot: slot)
        }
    }

    var forwarder: (any ProtocolForwarding)? {
        guard case .spy(_, let forwarder) = self else { return nil }
        return forwarder
    }
}

/// Owns one process-global invocation-registry entry.
///
/// Explicit cancellation lets ``StubResources`` remove callable registry
/// entries before destroying their executable trampoline arena. The fallback
/// `deinit` cleanup keeps a registration scoped even when construction exits
/// through a new failure path.
final class FabricatedInvocationRegistration: @unchecked Sendable {
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

    func cancel() {
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

/// Maps each fabricated witness table's stable context key to its invocation target.
enum FabricatedInvocationRegistry {
    private struct Entry {
        let identifier: UInt64
        let target: FabricatedInvocationTarget
    }

    nonisolated(unsafe) private static var storage: [UnsafeRawPointer: Entry] = [:]
    nonisolated(unsafe) private static var nextIdentifier: UInt64 = 0
    private static let lock = NSLock()

    static func register(
        _ target: FabricatedInvocationTarget,
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
                target: target
            )
            return identifier
        }
        return FabricatedInvocationRegistration(
            key: key,
            identifier: identifier
        )
    }

    @inline(__always)
    static func resolveOptional(
        _ key: UnsafeRawPointer
    ) -> FabricatedInvocationTarget? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]?.target
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
