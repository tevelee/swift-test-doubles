#if RUNTIME_STUB
import Echo

/// A typed runtime mock. No macros, no source access to the protocol needed.
///
/// ```swift
/// // Zero-config: signatures auto-discovered from the binary
/// let stub = RuntimeStub<any Calculator>()
///
/// stub.when { $0.add(1, 2) }.returns(42)
/// stub.when { $0.add(stub.any(), stub.any()) }.returns(0)
/// stub.when { $0.precision }.returns(5)
///
/// let sut = stub.proxy
/// sut.add(1, 2)  // → 42
/// ```
public class RuntimeStub<P>: @unchecked Sendable {
    let recorder: StubRecorder
    private let registryKey: UnsafeRawPointer
    private let allocationToDeallocate: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer
    private let trampolineAllocations: [UnsafeRawPointer]
    private let payload: AnyObject?

    struct PreparedStub {
        let recorder: StubRecorder
        let registryKey: UnsafeRawPointer
        let allocationToDeallocate: UnsafeMutableRawPointer
        let containerBytes: ExistentialContainer
        let trampolineAllocations: [UnsafeRawPointer]
        let payload: AnyObject?
    }

    init(prepared: PreparedStub) {
        self.recorder = prepared.recorder
        self.registryKey = prepared.registryKey
        self.allocationToDeallocate = prepared.allocationToDeallocate
        self.containerBytes = prepared.containerBytes
        self.trampolineAllocations = prepared.trampolineAllocations
        self.payload = prepared.payload
    }

    /// Create a thunk-backed stub. All method signatures are auto-discovered from
    /// the binary via dladdr + demangling.
    ///
    /// Requires that at least one type conforming to the protocol exists in the
    /// binary. Use ``makeFromModule(moduleName:)`` or explicit ``Slot`` /
    /// ``MethodDescriptor`` values when no conformer is available.
    public convenience init() {
        do {
            try self.init(prepared: Self.prepare())
        } catch {
            fatalError(Self.failureMessage(for: error))
        }
    }

    /// Throwing variant of the zero-config initializer.
    public static func make() throws -> RuntimeStub<P> {
        try RuntimeStub(prepared: prepare())
    }

    /// Create a stub by extracting protocol requirement signatures from the
    /// compiled Swift module rather than from an existing conformer's witness
    /// table. No real conformer is required.
    public static func makeFromModule(moduleName: String? = nil) throws -> RuntimeStub<P> {
        try RuntimeStub(prepared: prepareFromModule(moduleName: moduleName))
    }

    /// Create a stub with slot signatures — no method names needed.
    /// Slot order matches the protocol requirement enumeration. No real
    /// conformer is required.
    ///
    /// ```swift
    /// let stub = RuntimeStub<any Calculator>(
    ///     .method(Int.self, Int.self, returns: Int.self),   // slot 0: add
    ///     .method(Int.self, returns: String.self),           // slot 1: describe
    ///     .getter(Int.self),                                  // slot 2: precision
    /// )
    /// ```
    public convenience init(_ slots: Slot...) {
        do {
            try self.init(prepared: Self.prepare(slots: slots))
        } catch {
            fatalError(Self.failureMessage(for: error))
        }
    }

    /// Throwing variant of the slot-based initializer.
    public static func make(_ slots: Slot...) throws -> RuntimeStub<P> {
        try RuntimeStub(prepared: prepare(slots: slots))
    }

    /// Create a stub with explicit method descriptors for full control.
    /// No real conformer is required.
    public convenience init(methods: [MethodDescriptor]) {
        do {
            try self.init(prepared: Self.prepare(methods: methods))
        } catch {
            fatalError(Self.failureMessage(for: error))
        }
    }

    /// Throwing variant of the method-descriptor initializer.
    public static func make(methods: [MethodDescriptor]) throws -> RuntimeStub<P> {
        try RuntimeStub(prepared: prepare(methods: methods))
    }

    deinit {
        MockRegistry.remove(for: registryKey)
        for trampoline in trampolineAllocations {
            ThunkLibrary.destroyThunk(trampoline)
        }
        allocationToDeallocate.deallocate()
    }

    /// Use the stub directly as the protocol existential.
    /// ```swift
    /// let sut: any Calculator = stub()
    /// ```
    public func callAsFunction() -> P {
        let size = MemoryLayout<ExistentialContainer>.size
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<ExistentialContainer>.alignment)
        defer { ptr.deallocate() }
        var container = containerBytes
        if let payload {
            container.base.data.0 = Int(bitPattern: Unmanaged.passUnretained(payload).toOpaque())
        }
        ptr.storeBytes(of: container, as: ExistentialContainer.self)
        return ptr.load(as: P.self)
    }

    /// The protocol existential proxy.
    public var proxy: P { callAsFunction() }

    /// Recorded calls — forwarded from the recorder for convenience.
    public var calls: [RecordedCall] { recorder.calls }
}
#endif // RUNTIME_STUB
