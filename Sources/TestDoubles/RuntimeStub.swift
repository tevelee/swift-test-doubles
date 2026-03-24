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
public class RuntimeStub<P> {
    public let recorder: StubRecorder
    private let wtAllocation: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer

    // MARK: - Zero-config init: auto-discover everything

    /// Create a stub with zero configuration. All method signatures are
    /// auto-discovered from the binary via dladdr + demangling.
    ///
    /// Requires that at least one type conforming to the protocol exists
    /// in the binary (which it does if you import the module that defines it).
    public init() {
        let conformance = Self.findConformance()
        self.recorder = StubRecorder()

        // Auto-discover method signatures via dladdr + demangling
        let signatures = discoverSignatures(
            witnessTable: conformance.witnessTablePattern,
            proto: conformance.protocol
        )
        // Skip coroutines/associated types — keep real implementation for those
        let methods = signatures.compactMap { sig -> MethodDescriptor? in
            switch sig.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return nil
            default:
                return MethodDescriptor(name: sig.methodName, signature: sig.methodSignature, index: sig.slot)
            }
        }

        let (clonedWT, _) = Self.patchWitnessTable(from: conformance, methods: methods, recorder: recorder)
        self.wtAllocation = clonedWT
        self.containerBytes = Self.buildExistentialContainer(from: conformance, witnessTable: clonedWT)
    }

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
        let conformance = Self.findConformance()
        let proto = conformance.protocol
        precondition(slots.count == proto.numRequirements,
            "Expected \(proto.numRequirements) slots for '\(proto.name)', got \(slots.count)")

        self.recorder = StubRecorder()
        let methods = slots.enumerated().map { (i, slot) in
            MethodDescriptor(name: "slot_\(i)", signature: slot.signature, index: i)
        }

        let (clonedWT, _) = Self.patchWitnessTable(from: conformance, methods: methods, recorder: recorder)
        self.wtAllocation = clonedWT
        self.containerBytes = Self.buildExistentialContainer(from: conformance, witnessTable: clonedWT)
    }

    /// Create a stub with explicit method descriptors for full control.
    public init(methods: [MethodDescriptor]) {
        let conformance = Self.findConformance()
        self.recorder = StubRecorder()
        let (clonedWT, _) = Self.patchWitnessTable(from: conformance, methods: methods, recorder: recorder)
        self.wtAllocation = clonedWT
        self.containerBytes = Self.buildExistentialContainer(from: conformance, witnessTable: clonedWT)
    }

    deinit {
        MockRegistry.remove(for: UnsafeRawPointer(wtAllocation))
        wtAllocation.deallocate()
    }

    // MARK: - Use as protocol (#4: direct usage)

    /// Use the stub directly as the protocol existential.
    /// ```swift
    /// let sut: any Calculator = stub()
    /// ```
    public func callAsFunction() -> P {
        let size = MemoryLayout<ExistentialContainer>.size
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<ExistentialContainer>.alignment)
        defer { ptr.deallocate() }
        ptr.storeBytes(of: containerBytes, as: ExistentialContainer.self)
        return ptr.load(as: P.self)
    }

    /// The protocol existential proxy.
    public var proxy: P { callAsFunction() }

    /// Recorded calls — forwarded from the recorder for convenience.
    public var calls: [RecordedCall] { recorder.calls }

    // MARK: - When (#1: unified for getters, methods, and setters)

    /// Stub a method or getter.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) -> R) -> StubBuilder<R> {
        let recording = record { _ = call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a throwing method or getter.
    /// During recording, the thunk returns zero (never throws), so try! is safe.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R) -> StubBuilder<R> {
        let recording = record { _ = try! call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void method — auto-registers without needing `.performs()`. (#3)
    @discardableResult
    public func when(_ call: (P) -> Void) -> StubBuilder<Void> {
        let recording = record { call(self.callAsFunction()) }
        // Auto-register void stub (#3: no .performs() needed)
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a setter: `stub.when(setting: { $0.name = "x" })`
    @_disfavoredOverload
    @discardableResult
    public func when(setting call: (inout P) -> Void) -> StubBuilder<Void> {
        let recording = record {
            var mutable = self.callAsFunction()
            call(&mutable)
        }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    // MARK: - Verify (#5: concise)

    /// Verify a method/getter was called.
    public func verify(_ call: (P) -> some Any) -> VerifyBuilder {
        let recording = record(mode: .verifying) { _ = call(self.callAsFunction()) }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Verify a setter was called.
    public func verify(setting call: (inout P) -> Void) -> VerifyBuilder {
        let recording = record(mode: .verifying) {
            var mutable = self.callAsFunction()
            call(&mutable)
        }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Concise verify: `stub.verify(called: 2) { $0.add(1, 2) }` (#5)
    public func verify(called times: Int, _ call: (P) -> some Any) {
        let recording = record(mode: .verifying) { _ = call(self.callAsFunction()) }
        VerifyBuilder(recorder: recorder, recording: recording).wasCalled(times: times)
    }

    /// Concise verify never: `stub.verify(never: { $0.reset() })` (#5)
    public func verify(never call: (P) -> some Any) {
        verify(called: 0, call)
    }

    // MARK: - Internal recording

    private func record(mode: StubRecorder.Mode = .recording, _ block: () -> Void) -> RecordedCall {
        _matcherStack = [] // clear any stale matchers
        recorder.activeMatchers = []
        recorder.mode = mode
        block()
        // Collect matchers pushed by free functions during the closure (#2)
        if !_matcherStack.isEmpty {
            recorder.lastRecording?.matchers = _matcherStack
            _matcherStack = []
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    // MARK: - Internal helpers

    private static func findConformance() -> ConformanceDescriptor {
        let meta = reflect(P.self)
        guard let existential = meta as? ExistentialMetadata,
              let protoDesc = existential.protocols.first else {
            fatalError("Could not extract protocol from type \(P.self). Use `RuntimeStub<any YourProtocol>`.")
        }
        guard let conformance = Echo.findConformance(to: protoDesc) else {
            fatalError("""
            No conformance found for protocol '\(protoDesc.name)' in the binary. \
            Ensure at least one type conforming to \(protoDesc.name) is compiled into the test target.
            """)
        }
        return conformance
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
            recorder.refReturnFlags[method.index] = isReferenceReturn(method.signature.ret)
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
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in value() })
        return self
    }

    /// Dynamic stub — handler receives the actual arguments at call time.
    @discardableResult
    public func answers(_ handler: @escaping ([Any]) -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { handler($0) })
        return self
    }
}

extension StubBuilder where R == Void {
    @discardableResult
    public func performs(_ action: @escaping () -> Void = {}) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () }, action: { _ in action() })
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
