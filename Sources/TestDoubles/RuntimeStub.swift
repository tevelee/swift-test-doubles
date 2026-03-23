import Echo

/// A typed runtime mock. No macros, no source access to the protocol needed.
///
/// ```swift
/// let stub = RuntimeStub<any Calculator>([Int.self, String.self, Int.self])
///
/// stub.when { $0.add(1, 2) }.returns(42)
/// stub.when { $0.add(stub.any(), stub.any()) }.returns(0)
/// stub.when { $0.precision }.returns(5)
///
/// let sut = stub.proxy
/// sut.add(1, 2)  // → 42
/// ```
public class RuntimeStub<P> {
    public let recorder: StubRecorder
    private let wtAllocation: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer

    // MARK: - Init: return types only (Echo auto-discovers the rest)

    /// Create a stub with slot signatures — no method names needed.
    /// Slot order matches Echo's requirement enumeration.
    ///
    /// ```swift
    /// let stub = RuntimeStub<any Calculator>(
    ///     .method(Int.self, Int.self, returns: Int.self),   // slot 0: add
    ///     .method(Int.self, returns: String.self),           // slot 1: describe
    ///     .getter(Int.self),                                  // slot 2: precision
    /// )
    /// ```
    public init(_ slots: Slot...) {
        let protocolName = Self.extractProtocolName()
        guard let conformance = findConformance(toProtocolNamed: protocolName) else {
            fatalError("No conformance found for protocol '\(protocolName)' in the binary")
        }

        let proto = conformance.protocol
        precondition(slots.count == proto.numRequirements,
            "Expected \(proto.numRequirements) slots for '\(protocolName)', got \(slots.count)")

        self.recorder = StubRecorder()

        // Convert slots to method descriptors
        let methods = slots.enumerated().map { (i, slot) in
            MethodDescriptor(name: "slot_\(i)", signature: slot.signature, index: i)
        }

        let sourceWT = conformance.witnessTablePattern
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements
        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: totalWords * wordSize, alignment: wordSize)
        clonedWT.copyMemory(from: sourceWT.ptr, byteCount: totalWords * wordSize)
        self.wtAllocation = clonedWT

        for method in methods {
            guard let thunkPtr = ThunkLibrary.thunk(for: method.signature, slot: method.index) else {
                fatalError("No thunk for slot \(method.index) (\(method.signature))")
            }
            (clonedWT + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            recorder.setName(method.name, for: method.index)
        }

        MockRegistry.register(recorder, for: UnsafeRawPointer(clonedWT))

        self.containerBytes = Self.buildExistentialContainer(from: conformance, witnessTable: clonedWT)
    }

    /// Create a stub with explicit method descriptors for full control.
    public init(methods: [MethodDescriptor]) {
        let protocolName = Self.extractProtocolName()
        guard let conformance = findConformance(toProtocolNamed: protocolName) else {
            fatalError("No conformance found for '\(protocolName)'")
        }

        self.recorder = StubRecorder()
        let (clonedWT, _) = Self.patchWitnessTable(from: conformance, methods: methods, recorder: recorder)
        self.wtAllocation = clonedWT
        self.containerBytes = Self.buildExistentialContainer(from: conformance, witnessTable: clonedWT)
    }

    deinit {
        MockRegistry.remove(for: UnsafeRawPointer(wtAllocation))
        wtAllocation.deallocate()
    }

    // MARK: - Proxy

    /// The protocol existential proxy — use as your SUT or in when/verify closures.
    public var proxy: P {
        let size = MemoryLayout<ExistentialContainer>.size
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<ExistentialContainer>.alignment)
        defer { ptr.deallocate() }
        ptr.storeBytes(of: containerBytes, as: ExistentialContainer.self)
        return ptr.load(as: P.self)
    }

    // MARK: - When / Returns

    @discardableResult
    public func when<R>(_ call: (P) -> R) -> StubBuilder<R> {
        recorder.mode = .recording
        _ = call(proxy)
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the when closure")
        }
        recorder.lastRecording = nil
        return StubBuilder(recorder: recorder, recording: recording)
    }

    @discardableResult
    public func when(_ call: (P) -> Void) -> StubBuilder<Void> {
        recorder.mode = .recording
        call(proxy)
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the when closure")
        }
        recorder.lastRecording = nil
        return StubBuilder(recorder: recorder, recording: recording)
    }

    // MARK: - Verify

    public func verify(_ call: (P) -> some Any) -> VerifyBuilder {
        recorder.mode = .verifying
        _ = call(proxy)
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the verify closure")
        }
        recorder.lastRecording = nil
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    // MARK: - Matchers

    public func any<T>(_ type: T.Type = T.self) -> T {
        recorder.activeMatchers.append(AnyMatcher())
        return zeroValue(T.self)
    }

    public func equal<T: Equatable>(_ value: T) -> T {
        recorder.activeMatchers.append(EqualMatcher(expected: value))
        return value
    }

    public func match<T>(_ predicate: @escaping (T) -> Bool) -> T {
        recorder.activeMatchers.append(PredicateMatcher(predicate: predicate))
        return zeroValue(T.self)
    }

    // MARK: - Apply

    public func apply(to existential: inout P) {
        withUnsafeMutablePointer(to: &existential) { ptr in
            UnsafeMutableRawPointer(ptr).storeBytes(of: containerBytes, as: ExistentialContainer.self)
        }
    }

    // MARK: - Internal helpers

    /// Extract protocol name from the generic parameter P (e.g., `any Calculator` → "Calculator").
    private static func extractProtocolName() -> String {
        let meta = reflect(P.self)
        if let existential = meta as? ExistentialMetadata {
            guard let first = existential.protocols.first else {
                fatalError("Could not extract protocol from type \(P.self)")
            }
            return first.name
        }
        // Fallback: parse from type name
        let name = String(describing: P.self)
        return name.replacingOccurrences(of: "any ", with: "")
    }

    private static func patchWitnessTable(
        from conformance: ConformanceDescriptor,
        methods: [MethodDescriptor],
        recorder: StubRecorder
    ) -> (UnsafeMutableRawPointer, ProtocolDescriptor) {
        let proto = conformance.protocol
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements
        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: totalWords * wordSize, alignment: wordSize)
        clonedWT.copyMemory(from: conformance.witnessTablePattern.ptr, byteCount: totalWords * wordSize)

        for method in methods {
            guard let thunkPtr = ThunkLibrary.thunk(for: method.signature, slot: method.index) else {
                fatalError("No thunk for slot \(method.index) (\(method.signature))")
            }
            (clonedWT + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            recorder.setName(method.name, for: method.index)
        }

        MockRegistry.register(recorder, for: UnsafeRawPointer(clonedWT))
        return (clonedWT, proto)
    }

    private static func buildExistentialContainer(
        from conformance: ConformanceDescriptor,
        witnessTable: UnsafeMutableRawPointer
    ) -> ExistentialContainer {
        let typeDesc = conformance.contextDescriptor!
        let typeMetaPtr: UnsafeRawPointer
        if let sd = typeDesc as? StructDescriptor {
            typeMetaPtr = unsafeBitCast(sd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let cd = typeDesc as? ClassDescriptor {
            typeMetaPtr = unsafeBitCast(cd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let ed = typeDesc as? EnumDescriptor {
            typeMetaPtr = unsafeBitCast(ed.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else {
            fatalError("Unsupported type kind for '\(typeDesc.name)'")
        }

        let base = AnyExistentialContainer(type: unsafeBitCast(typeMetaPtr, to: Any.Type.self))
        return ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: UnsafeRawPointer(witnessTable))
        )
    }
}

// MARK: - StubBuilder

public struct StubBuilder<R> {
    let recorder: StubRecorder
    let recording: RecordedCall

    @discardableResult
    public func returns(_ value: @autoclosure @escaping () -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { value() })
        return self
    }

    @discardableResult
    public func answers(_ handler: @escaping ([Any]) -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { handler([]) })
        return self
    }
}

extension StubBuilder where R == Void {
    @discardableResult
    public func performs(_ action: @escaping () -> Void = {}) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { () }, action: { _ in action() })
        return self
    }
}

// MARK: - VerifyBuilder

public struct VerifyBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    public func wasCalled(times: Int? = nil) {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        let count = recorder.callCount(method: recording.methodIndex, matchers: matchers)
        if let expected = times {
            precondition(count == expected,
                "'\(recording.name)': expected \(expected) call(s), got \(count)")
        } else {
            precondition(count > 0,
                "'\(recording.name)': expected at least 1 call, got 0")
        }
    }

    public func wasNotCalled() { wasCalled(times: 0) }
}
