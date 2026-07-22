import Echo

/// Owns a concrete protocol existential at a stable address so its projected
/// value and witness tables remain valid for every forwarded call.
final class ForwardingTarget<P>: @unchecked Sendable {
    let witnessTables: [ProtocolLayout.DescriptorID: WitnessTable]

    private let storage: UnsafeMutableRawPointer
    private let representation: StubExistentialRepresentation
    private let valuePointer: UnsafeRawPointer
    private let objectPointer: UnsafeRawPointer?
    private let dynamicMetadata: UnsafeRawPointer

    init(
        _ target: P,
        layout: ProtocolLayout,
        representation: StubExistentialRepresentation
    ) throws {
        self.representation = representation
        storage = .allocate(
            byteCount: max(MemoryLayout<P>.size, 1),
            alignment: max(MemoryLayout<P>.alignment, 1)
        )
        storage.assumingMemoryBound(to: P.self).initialize(to: target)

        let witnessTableOffset: Int
        switch representation {
            case .opaque:
                let container = storage.assumingMemoryBound(
                    to: AnyExistentialContainer.self
                )
                valuePointer = container.pointee.projectValue()
                objectPointer = nil
                dynamicMetadata = (storage + 3 * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer.self)
                witnessTableOffset = 4

            case .classConstrained, .superclassConstrained:
                let object = storage.load(as: UnsafeRawPointer.self)
                objectPointer = object
                valuePointer = UnsafeRawPointer(storage)
                let instance = Unmanaged<AnyObject>.fromOpaque(object)
                    .takeUnretainedValue()
                dynamicMetadata = unsafeBitCast(
                    Swift.type(of: instance),
                    to: UnsafeRawPointer.self
                )
                witnessTableOffset = 1
        }

        let expectedWordCount = witnessTableOffset + layout.roots.count
        guard MemoryLayout<P>.size >= expectedWordCount * MemoryLayout<UInt>.size else {
            storage.assumingMemoryBound(to: P.self).deinitialize(count: 1)
            storage.deallocate()
            throw StubError.unsupportedProtocolShape(
                protocolName: String(reflecting: P.self),
                reason: "The forwarding target's existential storage does not contain the expected root witness tables."
            )
        }

        do {
            var tables: [ProtocolLayout.DescriptorID: WitnessTable] = [:]
            for (rootIndex, root) in layout.roots.enumerated() {
                let pointer =
                    (storage
                    + (witnessTableOffset + rootIndex) * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer.self)
                try Stub<P>.collectLinkedWitnessTables(
                    descriptor: root,
                    witnessTable: WitnessTable(ptr: pointer),
                    layout: layout,
                    into: &tables
                )
            }
            witnessTables = tables
        } catch {
            storage.assumingMemoryBound(to: P.self).deinitialize(count: 1)
            storage.deallocate()
            throw error
        }
    }

    deinit {
        storage.assumingMemoryBound(to: P.self).deinitialize(count: 1)
        storage.deallocate()
    }

    var selfValue: UnsafeRawPointer {
        switch representation {
            case .opaque:
                return valuePointer
            case .classConstrained, .superclassConstrained:
                guard let objectPointer else {
                    preconditionFailure(
                        "[TestDoubles] A class-constrained Spy target has no object pointer."
                    )
                }
                return objectPointer
        }
    }

    var metadata: UnsafeRawPointer { dynamicMetadata }
}
