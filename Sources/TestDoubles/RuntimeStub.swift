#if RUNTIME_STUB
import Echo
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
    private let registryKeyAllocation: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer

    struct PreparedStub {
        let recorder: StubRecorder
        let registryKeyAllocation: UnsafeMutableRawPointer
        let containerBytes: ExistentialContainer
    }

    init(prepared: PreparedStub) {
        self.recorder = prepared.recorder
        self.registryKeyAllocation = prepared.registryKeyAllocation
        self.containerBytes = prepared.containerBytes
    }

    // MARK: - Zero-config init (thunk-based)

    /// Create a thunk-backed stub. All method signatures are auto-discovered from
    /// the binary via dladdr + demangling.
    ///
    /// Requires that at least one type conforming to the protocol exists in the
    /// binary. Use ``CompiledStub`` on macOS when no conformer is available.
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

    /// Inspect environment constraints before creating a stub.
    public static func diagnose() -> RuntimeStubDiagnostics {
        let typeDescription = String(reflecting: P.self)
        let inferredModuleName = inferredModuleName()
        let runtimeCompilationSupported: Bool
        #if os(macOS)
        runtimeCompilationSupported = true
        #else
        runtimeCompilationSupported = false
        #endif

        guard let protoDesc = try? extractProtocolDescriptor() else {
            return RuntimeStubDiagnostics(
                typeDescription: typeDescription,
                protocolName: nil,
                requestedStrategy: "thunks",
                runtimeCompilationSupported: runtimeCompilationSupported,
                inferredModuleName: inferredModuleName,
                hasExistingConformance: false,
                notes: [
                    "Use `RuntimeStub<any YourProtocol>` so the generic type is a protocol existential."
                ]
            )
        }

        let hasExistingConformance = Echo.findConformance(to: protoDesc) != nil
        var notes: [String] = []

        if hasExistingConformance {
            notes.append("A real conformer already exists in the binary — RuntimeStub can use runtime discovery.")
        } else {
            notes.append("No existing conformer was found in the current binary.")
            notes.append("RuntimeStub needs at least one real conformer. Use CompiledStub on macOS when none is available.")
        }

        return RuntimeStubDiagnostics(
            typeDescription: typeDescription,
            protocolName: protoDesc.name,
            requestedStrategy: "thunks",
            runtimeCompilationSupported: runtimeCompilationSupported,
            inferredModuleName: inferredModuleName,
            hasExistingConformance: hasExistingConformance,
            notes: notes
        )
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
        MockRegistry.remove(for: UnsafeRawPointer(registryKeyAllocation))
        registryKeyAllocation.deallocate()
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

    /// Stub a void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) -> Void) -> StubBuilder<Void> {
        let recording = record { call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void throwing method — auto-registers.
    @discardableResult
    public func when(_ call: (P) throws -> Void) -> StubBuilder<Void> {
        let recording = record { try! call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async -> R) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = await call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async throwing method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async throws -> R) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = try! await call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) async -> Void) async -> StubBuilder<Void> {
        let recording = await recordAsync { await call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async throwing void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) async throws -> Void) async -> StubBuilder<Void> {
        let recording = await recordAsync { try! await call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    // MARK: - when/then (trailing closure style)

    /// Stub with a static value:
    /// `stub.when { $0.find(id: any()) } then: { "Alice" }`
    @discardableResult
    public func when<R>(_ call: (P) -> R, then handler: @escaping () -> R) -> StubBuilder<R> {
        let builder = when(call)
        builder.returns(handler())
        return builder
    }

    /// Stub with dynamic args:
    /// `stub.when { $0.find(id: any()) } then: { args in "user_\(args[0])" }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) -> R, then handler: @escaping ([Any]) -> R) -> StubBuilder<R> {
        let builder = when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { handler($0) })
        return builder
    }

    /// Throwing stub:
    /// `stub.when { try $0.read(path: any()) } then: { "content" }`
    /// `stub.when { try $0.read(path: any()) } then: { throw NotFoundError() }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R, then handler: @escaping () throws -> R) -> StubBuilder<R> {
        let builder: StubBuilder<R> = when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addThrowingStub(method: builder.recording.methodIndex, matchers: matchers) { _ in try handler() }
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { _ in try! handler() })
        return builder
    }

    /// Throwing stub with dynamic args:
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R, then handler: @escaping ([Any]) throws -> R) -> StubBuilder<R> {
        let builder: StubBuilder<R> = when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addThrowingStub(method: builder.recording.methodIndex, matchers: matchers, handler: handler)
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { try! handler($0) })
        return builder
    }

    /// Async stub:
    /// `await stub.when { try await $0.load(url: any()) } then: { "data" }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async throws -> R, then handler: @escaping () throws -> R) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addThrowingStub(method: builder.recording.methodIndex, matchers: matchers) { _ in try handler() }
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { _ in try! handler() })
        return builder
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

    // MARK: - Throwing verify variants

    /// Verify a throwing method/getter was called.
    public func verify(_ call: (P) throws -> some Any) -> VerifyBuilder {
        let recording = record(mode: .verifying) { _ = try! call(self.callAsFunction()) }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Concise throwing verify: `stub.verify(called: 2) { try $0.load(path: any()) }`
    public func verify(called times: Int, _ call: (P) throws -> some Any) {
        let recording = record(mode: .verifying) { _ = try! call(self.callAsFunction()) }
        VerifyBuilder(recorder: recorder, recording: recording).wasCalled(times: times)
    }

    /// Concise throwing verify never: `stub.verify(never: { try $0.load(path: any()) })`
    public func verify(never call: (P) throws -> some Any) {
        verify(called: 0, call)
    }

    /// Verify that methods were called in a specific order.
    /// ```swift
    /// stub.verifyOrder {
    ///     $0.find(id: 1)
    ///     $0.save(name: "x", age: 1)
    /// }
    /// ```
    public func verifyOrder(_ calls: (P) -> Void) {
        recorder.mode = .normal  // calls execute normally
        var expectedOrder: [Int] = []
        let originalCalls = recorder.calls

        // Record which methods are called in the closure by tracking the call log
        let beforeCount = recorder.calls.count
        calls(self.callAsFunction())
        let newCalls = Array(recorder.calls[beforeCount...])
        expectedOrder = newCalls.map(\.methodIndex)

        // Restore original call log
        recorder.calls = Array(originalCalls)

        // Find matching calls in original log in order
        var searchFrom = 0
        for (i, expectedMethod) in expectedOrder.enumerated() {
            guard let idx = recorder.calls[searchFrom...].firstIndex(where: { $0.methodIndex == expectedMethod }) else {
                preconditionFailure("verifyOrder: call \(i) (\(recorder.calls.first { $0.methodIndex == expectedMethod }?.name ?? "method_\(expectedMethod)")) not found after position \(searchFrom)")
            }
            searchFrom = idx + 1
        }
    }

    // MARK: - Internal recording

    func recordAsync(mode: StubRecorder.Mode = .recording, _ block: () async -> Void) async -> RecordedCall {
        MatcherContext.begin()
        recorder.activeMatchers = []
        recorder.mode = mode
        await block()
        let asyncMatchers = MatcherContext.end()
        if !asyncMatchers.isEmpty {
            recorder.lastRecording?.matchers = asyncMatchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the async closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    private func record(mode: StubRecorder.Mode = .recording, _ block: () -> Void) -> RecordedCall {
        MatcherContext.begin()
        recorder.activeMatchers = []
        recorder.mode = mode
        block()
        let matchers = MatcherContext.end()
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    // MARK: - Internal helpers

    private static func prepare() throws -> PreparedStub {
        let conformance = try findConformance()
        let signatures = discoverSignatures(
            witnessTable: conformance.witnessTablePattern,
            proto: conformance.protocol
        )
        let mockableSigs = mockableSignatures(from: signatures)
        let methods = mockableSigs.map { sig in
            MethodDescriptor(name: sig.methodName, signature: sig.methodSignature, index: sig.slot)
        }
        return try prepareThunk(from: conformance, methods: methods)
    }

    private static func prepare(slots: [Slot]) throws -> PreparedStub {
        let conformance = try findConformance()
        let proto = conformance.protocol
        let mockableIndices = proto.requirements.enumerated().compactMap { i, req -> Int? in
            switch req.flags.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return nil
            default:
                return i
            }
        }

        guard slots.count == mockableIndices.count else {
            throw RuntimeStubError.slotCountMismatch(
                protocolName: proto.name,
                expected: mockableIndices.count,
                actual: slots.count
            )
        }

        let methods = zip(slots, mockableIndices).enumerated().map { userIdx, pair in
            MethodDescriptor(name: "slot_\(userIdx)", signature: pair.0.signature, index: pair.1)
        }

        let prepared = try prepareThunk(from: conformance, methods: methods)
        for reqIdx in mockableIndices {
            prepared.recorder.refReturnFlags[reqIdx] = false
        }
        return prepared
    }

    private static func prepare(methods: [MethodDescriptor]) throws -> PreparedStub {
        try prepareThunk(from: findConformance(), methods: methods)
    }

    private static func prepareThunk(
        from conformance: ConformanceDescriptor,
        methods: [MethodDescriptor]
    ) throws -> PreparedStub {
        let recorder = StubRecorder()
        let clonedWT = try patchWitnessTable(from: conformance, methods: methods, recorder: recorder)
        let containerBytes = try buildExistentialContainer(from: conformance, witnessTable: clonedWT)
        return PreparedStub(recorder: recorder, registryKeyAllocation: clonedWT, containerBytes: containerBytes)
    }

    private static func extractProtocolDescriptor() throws -> ProtocolDescriptor {
        let meta = reflect(P.self)
        guard let existential = meta as? ExistentialMetadata,
              let protoDesc = existential.protocols.first else {
            throw RuntimeStubError.typeIsNotProtocol(typeDescription: String(reflecting: P.self))
        }
        return protoDesc
    }

    private static func inferredModuleName() -> String? {
        var typeDescription = String(reflecting: P.self)
        if typeDescription.hasPrefix("any ") {
            typeDescription.removeFirst(4)
        }
        guard !typeDescription.contains("&") else { return nil }
        let parts = typeDescription.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return String(parts[0])
    }

    private static func findConformance() throws -> ConformanceDescriptor {
        let protoDesc = try extractProtocolDescriptor()
        guard let conformance = Echo.findConformance(to: protoDesc) else {
            throw RuntimeStubError.noConformanceFound(
                protocolName: protoDesc.name,
                typeDescription: String(reflecting: P.self)
            )
        }
        return conformance
    }

    private static func patchWitnessTable(
        from conformance: ConformanceDescriptor,
        methods: [MethodDescriptor],
        recorder: StubRecorder
    ) throws -> UnsafeMutableRawPointer {
        let proto = conformance.protocol
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements
        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: totalWords * wordSize, alignment: wordSize)
        clonedWT.copyMemory(from: conformance.witnessTablePattern.ptr, byteCount: totalWords * wordSize)

        for method in methods {
            guard let thunkPtr = ThunkLibrary.thunk(for: method.signature, slot: method.index) else {
                throw RuntimeStubError.missingThunk(slot: method.index, signature: method.signature)
            }
            (clonedWT + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            recorder.setName(method.name, for: method.index)
            recorder.refReturnFlags[method.index] = isReferenceReturn(method.signature.ret)
        }

        MockRegistry.register(recorder, for: UnsafeRawPointer(clonedWT))
        return clonedWT
    }

    private static func buildExistentialContainer(
        from conformance: ConformanceDescriptor,
        witnessTable: UnsafeMutableRawPointer
    ) throws -> ExistentialContainer {
        guard let typeDesc = conformance.contextDescriptor else {
            throw RuntimeStubError.unsupportedTypeKind(typeName: conformance.protocol.name)
        }
        let typeMetaPtr: UnsafeRawPointer
        if let sd = typeDesc as? StructDescriptor {
            typeMetaPtr = unsafeBitCast(sd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let cd = typeDesc as? ClassDescriptor {
            typeMetaPtr = unsafeBitCast(cd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let ed = typeDesc as? EnumDescriptor {
            typeMetaPtr = unsafeBitCast(ed.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else {
            throw RuntimeStubError.unsupportedTypeKind(typeName: typeDesc.name)
        }

        let base = AnyExistentialContainer(type: unsafeBitCast(typeMetaPtr, to: Any.Type.self))
        return ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: UnsafeRawPointer(witnessTable))
        )
    }

    private static func mockableSignatures(from signatures: [DiscoveredSignature]) -> [DiscoveredSignature] {
        signatures.filter { sig in
            switch sig.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return false
            default:
                return true
            }
        }
    }

    private static func failureMessage(for error: Error) -> String {
        if let error = error as? RuntimeStubError {
            return "[TestDoubles] \(error.description)"
        }
        return "[TestDoubles] \(String(describing: error))"
    }
}

// MARK: - StubBuilder

/// Configures the return value or action for a stubbed method.
/// Returned by ``RuntimeStub/when(_:)-4hxsd``.
public struct StubBuilder<R> {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Return a static value.
    /// ```swift
    /// stub.when { $0.find(id: any()) }.returns("Alice")
    /// ```
    @discardableResult
    public func returns(_ value: @autoclosure @escaping () -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in value() })
        return self
    }

    // MARK: - .then API

    /// Unified stub handler — can return values or throw errors.
    /// ```swift
    /// stub.when { try $0.read(path: any()) }.then { "content" }
    /// stub.when { try $0.read(path: any()) }.then { throw NotFoundError() }
    /// stub.when { try $0.read(path: any()) }.then { args in "path: \(args[0])" }
    /// ```
    @discardableResult
    public func then(_ handler: @escaping ([Any]) throws -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addThrowingStub(method: recording.methodIndex, matchers: matchers, handler: handler)
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { args in
            try! handler(args)
        })
        return self
    }

    /// Convenience: no-args handler.
    /// ```swift
    /// stub.when { try $0.read(path: any()) }.then { "content" }
    /// stub.when { try $0.read(path: any()) }.then { throw NotFoundError() }
    /// ```
    @discardableResult
    public func then(_ handler: @escaping () throws -> R) -> Self {
        then { _ in try handler() }
    }
}

// MARK: - VerifyBuilder

/// Asserts that a stubbed method was called the expected number of times.
/// Returned by ``RuntimeStub/verify(_:)-6f6ij``.
public struct VerifyBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Assert the method was called (at least once, or exactly `times` times).
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

    /// Assert the method was never called.
    public func wasNotCalled() { wasCalled(times: 0) }

    /// Inspect arguments of matching calls.
    /// ```swift
    /// stub.verify { $0.find(id: any()) }.withArgs { calls in
    ///     XCTAssertEqual(calls[0][0] as! Int, 42)
    /// }
    /// ```
    public func withArgs(_ handler: ([[Any]]) -> Void) {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        let matching = recorder.calls.filter { call in
            call.methodIndex == recording.methodIndex &&
            (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }
        handler(matching.map(\.args))
    }

    private func matchArgs(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }
}
#endif // RUNTIME_STUB
