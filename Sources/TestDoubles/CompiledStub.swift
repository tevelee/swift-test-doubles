#if COMPILED_STUB && os(macOS)
import Echo
import Foundation
import Darwin

/// A typed mock built by compiling a Swift source file at test startup.
///
/// Use this when no real conformer exists in the test binary and you are on macOS.
/// The first use per protocol type takes ~1–2 s to compile; subsequent uses are cached.
///
/// ```swift
/// let stub = try CompiledStub<any PrototypeCalculator> {
///     $0.method("add", args: [.int(), .int()], returns: .int)
///     $0.method("describe", args: [.int()], returns: .string)
///     $0.getter("precision", type: .int)
/// }
///
/// stub.when { $0.add(1, 2) }.returns(3)
/// stub.when { $0.precision }.returns(10)
///
/// let sut: any PrototypeCalculator = stub()
/// assert(sut.add(1, 2) == 3)
/// ```
public class CompiledStub<P>: @unchecked Sendable {
    let recorder: StubRecorder
    private let registryKeyAllocation: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer

    private init(recorder: StubRecorder, registryKeyAllocation: UnsafeMutableRawPointer, containerBytes: ExistentialContainer) {
        self.recorder = recorder
        self.registryKeyAllocation = registryKeyAllocation
        self.containerBytes = containerBytes
    }

    deinit {
        MockRegistry.remove(for: UnsafeRawPointer(registryKeyAllocation))
        registryKeyAllocation.deallocate()
    }

    // MARK: - Initializers

    /// Create a compiled stub with explicit method signatures.
    ///
    /// No real conformer is required. Signatures are described via the builder:
    /// ```swift
    /// let stub = try CompiledStub<any MyProtocol> {
    ///     $0.method("doWork", args: [.string("input")], returns: .bool)
    ///     $0.getter("title", type: .string)
    /// }
    /// ```
    public convenience init(_ build: (inout SignatureBuilder) -> Void) throws {
        let signatures = [DiscoveredSignature].describing(build)
        let protoName = try Self.protocolName()
        let moduleName = try Self.resolveModuleName()
        let prepared = try Self.compileWith(protocolName: protoName, moduleName: moduleName, signatures: signatures)
        self.init(recorder: prepared.recorder, registryKeyAllocation: prepared.contextKey, containerBytes: prepared.containerBytes)
    }

    /// Create a compiled stub by auto-discovering signatures from an existing conformer.
    ///
    /// Requires at least one type conforming to the protocol to be linked into the binary.
    /// Use the explicit-signatures init when no conformer is available.
    public convenience init() throws {
        let protoDesc = try Self.extractProtocolDescriptor()
        guard let conformance = Echo.findConformance(to: protoDesc) else {
            throw RuntimeStubError.noConformanceFound(
                protocolName: protoDesc.name,
                typeDescription: String(reflecting: P.self)
            )
        }
        let signatures = discoverSignatures(
            witnessTable: conformance.witnessTablePattern,
            proto: conformance.protocol
        )
        let moduleName = try Self.resolveModuleName()
        let prepared = try Self.compileWith(protocolName: protoDesc.name, moduleName: moduleName, signatures: signatures)
        self.init(recorder: prepared.recorder, registryKeyAllocation: prepared.contextKey, containerBytes: prepared.containerBytes)
    }

    // MARK: - Use as protocol

    /// Return the stub as the protocol existential.
    /// ```swift
    /// let sut: any MyProtocol = stub()
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

    /// Recorded calls for this stub.
    public var calls: [RecordedCall] { recorder.calls }

    // MARK: - When

    /// Stub a method or getter.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) -> R) -> StubBuilder<R> {
        let recording = record { _ = call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a throwing method or getter.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R) -> StubBuilder<R> {
        let recording = record { _ = try! call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) -> Void) -> StubBuilder<Void> {
        let recording = record { call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(
            method: recording.methodIndex,
            matchers: matchers,
            returnValue: { _ in () },
            isFallback: true
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void throwing method — auto-registers.
    @discardableResult
    public func when(_ call: (P) throws -> Void) -> StubBuilder<Void> {
        let recording = record { try! call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(
            method: recording.methodIndex,
            matchers: matchers,
            returnValue: { _ in () },
            isFallback: true
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async method. Void requirements are auto-registered.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async -> R) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = await call(self.callAsFunction()) }
        if R.self == Void.self {
            let matchers = recording.matchers.isEmpty
                ? recording.args.map { DescriptionMatcher(value: $0) }
                : recording.matchers
            recorder.addStub(
                method: recording.methodIndex,
                matchers: matchers,
                returnValue: { _ in () },
                isFallback: true
            )
        }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async throwing method. Void requirements are auto-registered.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async throws -> R) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = try! await call(self.callAsFunction()) }
        if R.self == Void.self {
            let matchers = recording.matchers.isEmpty
                ? recording.args.map { DescriptionMatcher(value: $0) }
                : recording.matchers
            recorder.addStub(
                method: recording.methodIndex,
                matchers: matchers,
                returnValue: { _ in () },
                isFallback: true
            )
        }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    // MARK: - Verify

    /// Verify a method/getter was called.
    public func verify(_ call: (P) -> some Any) -> VerifyBuilder {
        let recording = record(mode: .verifying) { _ = call(self.callAsFunction()) }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Verify a throwing method/getter was called.
    public func verify(_ call: (P) throws -> some Any) -> VerifyBuilder {
        let recording = record(mode: .verifying) { _ = try! call(self.callAsFunction()) }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Concise verify: `stub.verify(called: 2) { $0.add(1, 2) }`
    public func verify(called times: Int, _ call: (P) -> some Any) {
        let recording = record(mode: .verifying) { _ = call(self.callAsFunction()) }
        VerifyBuilder(recorder: recorder, recording: recording).wasCalled(times: times)
    }

    /// Concise verify never: `stub.verify(never: { $0.reset() })`
    public func verify(never call: (P) -> some Any) {
        verify(called: 0, call)
    }

    // MARK: - Internal recording

    func recordAsync(mode: StubRecorder.Mode = .recording, _ block: () async -> Void) async -> RecordedCall {
        let (_, matchers) = await MatcherContext.withRecording {
            recorder.mode = mode
            await block()
        }
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the async closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    private func record(mode: StubRecorder.Mode = .recording, _ block: () -> Void) -> RecordedCall {
        if mode == .verifying {
            recorder.verificationRecordings = []
        }
        let (_, matchers) = MatcherContext.withRecording {
            recorder.mode = mode
            block()
        }
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the closure")
        }
        recorder.lastRecording = nil
        if mode == .verifying {
            recorder.verificationRecordings = []
        }
        return recording
    }

    // MARK: - Compilation helpers

    private struct Prepared {
        let recorder: StubRecorder
        let contextKey: UnsafeMutableRawPointer
        let containerBytes: ExistentialContainer
    }

    private static func compileWith(
        protocolName: String,
        moduleName: String,
        signatures: [DiscoveredSignature]
    ) throws -> Prepared {
        guard let handle = RuntimeCompiler.compileMock(
            protocolName: protocolName,
            moduleName: moduleName,
            signatures: signatures
        ) else {
            throw RuntimeStubError.runtimeCompilerFailed(
                protocolName: protocolName,
                moduleName: moduleName,
                details: RuntimeCompiler.lastFailure?.description
            )
        }

        typealias Accessor = @convention(c) () -> UnsafeRawPointer
        guard let getWT = dlsym(handle, "swift_mock_witness_table") else {
            throw RuntimeStubError.missingCompiledSymbol(protocolName: protocolName, symbol: "swift_mock_witness_table")
        }
        guard let getMeta = dlsym(handle, "swift_mock_type_metadata") else {
            throw RuntimeStubError.missingCompiledSymbol(protocolName: protocolName, symbol: "swift_mock_type_metadata")
        }

        let wtPtr = unsafeBitCast(getWT, to: Accessor.self)()
        let metaPtr = unsafeBitCast(getMeta, to: Accessor.self)()

        let recorder = StubRecorder()
        for sig in signatures where sig.kind == .method || sig.kind == .getter {
            recorder.setName(sig.methodName, for: sig.slot)
        }

        let alignment = MemoryLayout<UnsafeRawPointer>.alignment
        let contextKey = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<UnsafeRawPointer>.size,
            alignment: alignment
        )
        contextKey.storeBytes(of: UInt(bitPattern: contextKey), as: UInt.self)
        MockRegistry.register(recorder, for: UnsafeRawPointer(contextKey))

        var base = AnyExistentialContainer(type: unsafeBitCast(metaPtr, to: Any.Type.self))
        withUnsafeMutablePointer(to: &base) { ptr in
            UnsafeMutableRawPointer(ptr).storeBytes(of: UnsafeRawPointer(contextKey), as: UnsafeRawPointer.self)
        }

        let containerBytes = ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: wtPtr)
        )

        return Prepared(recorder: recorder, contextKey: contextKey, containerBytes: containerBytes)
    }

    private static func extractProtocolDescriptor() throws -> ProtocolDescriptor {
        let meta = reflect(P.self)
        guard let existential = meta as? ExistentialMetadata,
              let protoDesc = existential.protocols.first else {
            throw RuntimeStubError.typeIsNotProtocol(typeDescription: String(reflecting: P.self))
        }
        return protoDesc
    }

    private static func protocolName() throws -> String {
        try extractProtocolDescriptor().name
    }

    private static func resolveModuleName() throws -> String {
        var typeDescription = String(reflecting: P.self)
        if typeDescription.hasPrefix("any ") { typeDescription.removeFirst(4) }
        guard !typeDescription.contains("&") else {
            throw RuntimeStubError.moduleNameCouldNotBeInferred(typeDescription: String(reflecting: P.self))
        }
        let parts = typeDescription.split(separator: ".")
        guard parts.count >= 2 else {
            throw RuntimeStubError.moduleNameCouldNotBeInferred(typeDescription: String(reflecting: P.self))
        }
        return String(parts[0])
    }
}
#endif // COMPILED_STUB && os(macOS)
