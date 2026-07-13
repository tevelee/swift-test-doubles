import Echo

/// A runtime-generated test double for a protocol existential.
///
/// Use the throwing initializer without requirements when a conforming type is
/// linked into the process. Supply ``Requirement`` values when no conformer is
/// available.
///
/// ```swift
/// let stub = try Stub<any Calculator>()
/// stub.when { $0.add(1, 2) }.returns(42)
///
/// let calculator: any Calculator = stub()
/// ```
public final class Stub<P>: @unchecked Sendable {
    let recorder: StubRecorder
    private let resources: StubResources
    private let containerBytes: ExistentialContainer
    private let payload: AnyObject?

    struct PreparedStub {
        let recorder: StubRecorder
        let resources: StubResources
        let containerBytes: ExistentialContainer
        let payload: AnyObject?
    }

    init(prepared: PreparedStub) {
        self.recorder = prepared.recorder
        self.resources = prepared.resources
        self.containerBytes = prepared.containerBytes
        self.payload = prepared.payload
    }

    /// Creates a stub from runtime-discovered or explicitly supplied
    /// requirement signatures.
    ///
    /// With no arguments, the stub discovers signatures from an existing
    /// conformer's witness table. Explicit requirements remove that dependency
    /// and must appear in protocol requirement order. When a discoverable
    /// conformance is linked, every reliably discoverable signature component
    /// is also used to validate explicitly supplied requirements.
    public convenience init(_ requirements: Requirement...) throws {
        let prepared = if requirements.isEmpty {
            try Self.prepare()
        } else {
            try Self.prepare(requirements: requirements)
        }
        self.init(prepared: prepared)
    }

    /// Returns the generated protocol existential.
    public func callAsFunction() -> P {
        let size = MemoryLayout<ExistentialContainer>.size
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: MemoryLayout<ExistentialContainer>.alignment
        )
        defer { ptr.deallocate() }

        var container = containerBytes
        if let payload {
            container.base.data.0 = Int(bitPattern: Unmanaged.passUnretained(payload).toOpaque())
        }
        ptr.storeBytes(of: container, as: ExistentialContainer.self)
        return ptr.load(as: P.self)
    }
}
