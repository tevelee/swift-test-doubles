import Echo

/// Couples one fabricated existential's ABI storage with the object that owns
/// its runtime resources.
struct FabricatedExistentialStorage<P> {
    private let words: [UInt]
    private let payload: AnyObject

    init(
        witnessTables: [UnsafeMutableRawPointer],
        representation: StubExistentialRepresentation,
        payload: AnyObject
    ) throws {
        let wordSize = MemoryLayout<UInt>.size
        var words: [UInt]
        switch representation {
            case .opaque:
                var base = AnyExistentialContainer(type: StubPayload.self)
                words = withUnsafeBytes(of: &base) { bytes in
                    stride(from: 0, to: bytes.count, by: wordSize).map {
                        bytes.load(fromByteOffset: $0, as: UInt.self)
                    }
                }

            case .classConstrained, .superclassConstrained:
                // A class existential stores the object reference directly,
                // followed by one witness table for each root protocol. The
                // object word is populated during materialization so every
                // returned existential receives a strong reference to the
                // shared payload.
                words = [0]
        }
        words.append(
            contentsOf: witnessTables.map {
                UInt(bitPattern: UnsafeRawPointer($0))
            })

        let expectedSize = words.count * wordSize
        guard MemoryLayout<P>.size == expectedSize,
            MemoryLayout<P>.alignment <= MemoryLayout<UInt>.alignment
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: String(reflecting: P.self),
                reason: "Existential storage is \(MemoryLayout<P>.size) bytes, but runtime metadata requires \(expectedSize) bytes."
            )
        }

        self.words = words
        self.payload = payload
    }

    func materialize() -> P {
        let size = MemoryLayout<P>.size
        precondition(
            size == words.count * MemoryLayout<UInt>.size,
            "[TestDoubles] Fabricated existential storage no longer matches its runtime metadata."
        )
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: MemoryLayout<P>.alignment
        )
        defer { pointer.deallocate() }

        words.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            pointer.copyMemory(from: baseAddress, byteCount: size)
        }
        pointer.storeBytes(
            of: UInt(bitPattern: Unmanaged.passUnretained(payload).toOpaque()),
            as: UInt.self
        )
        return withExtendedLifetime(payload) {
            pointer.load(as: P.self)
        }
    }
}
