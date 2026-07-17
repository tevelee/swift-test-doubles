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
    case dummy(DummyInvocation)

    func recorderOrReject(slot: Int) -> StubRecorder {
        switch self {
            case .stub(let recorder):
                return recorder
            case .dummy(let invocation):
                invocation.reject(slot: slot)
        }
    }
}

/// Maps each fabricated witness table's stable context key to its invocation target.
enum FabricatedInvocationRegistry {
    nonisolated(unsafe) private static var storage: [UnsafeRawPointer: FabricatedInvocationTarget] = [:]
    private static let lock = NSLock()

    static func register(
        _ target: FabricatedInvocationTarget,
        for key: UnsafeRawPointer
    ) {
        lock.lock()
        defer { lock.unlock() }
        precondition(
            storage[key] == nil,
            "[TestDoubles] A fabricated witness table was registered more than once."
        )
        storage[key] = target
    }

    static func remove(for key: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    @inline(__always)
    static func resolveOptional(
        _ key: UnsafeRawPointer
    ) -> FabricatedInvocationTarget? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}
