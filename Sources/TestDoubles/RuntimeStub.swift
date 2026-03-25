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
    public let recorder: StubRecorder
    private let wtAllocation: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer

    // MARK: - Zero-config init: auto-discover everything

    /// Create a stub with zero configuration. All method signatures are
    /// auto-discovered from the binary via dladdr + demangling.
    ///
    /// Requires that at least one type conforming to the protocol exists
    /// in the binary (which it does if you import the module that defines it).
    /// Mock generation strategy.
    public enum Strategy {
        /// Use pre-compiled ABI-class thunks. Fast, no external tools needed.
        /// Limited to ≤16-byte return types, no real error propagation.
        case thunks
        /// Compile a conforming type at test startup via swiftc.
        /// Supports any type, throws, async. Requires swiftc on PATH.
        case compiled
        /// Try compiled first, fall back to thunks if compilation fails.
        case auto
    }

    /// Zero-config init with strategy selection.
    /// ```swift
    /// let stub = RuntimeStub<any MyService>()                    // auto
    /// let stub = RuntimeStub<any MyService>(strategy: .compiled) // force compilation
    /// let stub = RuntimeStub<any MyService>(strategy: .thunks)   // skip compilation
    /// ```
    public init(strategy: Strategy = .auto) {
        let conformance = Self.findConformance()
        self.recorder = StubRecorder()

        let signatures = discoverSignatures(
            witnessTable: conformance.witnessTablePattern,
            proto: conformance.protocol
        )

        let mockableSigs = signatures.filter { sig in
            switch sig.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return false
            default:
                return true
            }
        }

        let shouldCompile: Bool
        switch strategy {
        case .thunks: shouldCompile = false
        case .compiled: shouldCompile = true
        case .auto:
            shouldCompile = mockableSigs.contains { $0.isThrowing || $0.isAsync }
        }

        if shouldCompile {
            let proto = conformance.protocol
            let moduleName = mockableSigs.compactMap { RuntimeCompiler.extractModuleName(from: $0.rawDemangled) }.first
                ?? "UnknownModule"

            if let handle = RuntimeCompiler.compileMock(
                protocolName: proto.name,
                moduleName: moduleName,
                signatures: signatures
            ) {
                // Use dlsym to get the self-describing accessors from the compiled dylib.
                // This avoids Echo.types which crashes on dynamically loaded images.
                typealias Accessor = @convention(c) () -> UnsafeRawPointer
                if let getWT = dlsym(handle, "td_mock_witness_table"),
                   let getMeta = dlsym(handle, "td_mock_type_metadata") {

                let wtPtr = unsafeBitCast(getWT, to: Accessor.self)()
                let metaPtr = unsafeBitCast(getMeta, to: Accessor.self)()

                let totalWords = 1 + proto.numRequirements
                let wordSize = MemoryLayout<UnsafeRawPointer>.size
                let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: totalWords * wordSize, alignment: wordSize)
                clonedWT.copyMemory(from: wtPtr, byteCount: totalWords * wordSize)

                MockRegistry.register(recorder, for: UnsafeRawPointer(clonedWT))

                for sig in mockableSigs {
                    recorder.setName(sig.methodName, for: sig.slot)
                }

                self.wtAllocation = clonedWT

                var base = AnyExistentialContainer(type: unsafeBitCast(metaPtr, to: Any.Type.self))
                withUnsafeMutablePointer(to: &base) { ptr in
                    UnsafeMutableRawPointer(ptr).storeBytes(of: UnsafeRawPointer(clonedWT), as: UnsafeRawPointer.self)
                }
                self.containerBytes = ExistentialContainer(
                    base: base,
                    witnessTable: WitnessTable(ptr: UnsafeRawPointer(clonedWT))
                )
                return
                }
            }

            if strategy == .compiled {
                preconditionFailure("""
                [TestDoubles] RuntimeCompiler failed for '\(proto.name)'. \
                Ensure the protocol's module is importable and swiftc version matches the build toolchain. \
                Use strategy: .auto to fall back to thunks.
                """)
            }
        }

        // Standard thunk-based approach (works for non-throwing/non-async methods)
        let methods = mockableSigs.map { sig in
            MethodDescriptor(name: sig.methodName, signature: sig.methodSignature, index: sig.slot)
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

        // Find the requirement indices that are actually mockable
        // (skip coroutines, associated types, base protocol conformances)
        let mockableIndices = proto.requirements.enumerated().compactMap { i, req -> Int? in
            switch req.flags.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return nil
            default:
                return i
            }
        }

        precondition(slots.count == mockableIndices.count,
            "Expected \(mockableIndices.count) slots for '\(proto.name)', got \(slots.count)")

        self.recorder = StubRecorder()
        let methods = zip(slots, mockableIndices).enumerated().map { userIdx, pair in
            MethodDescriptor(name: "slot_\(userIdx)", signature: pair.0.signature, index: pair.1)
        }

        let (clonedWT, _) = Self.patchWitnessTable(from: conformance, methods: methods, recorder: recorder)

        // For slot-based init, disable retain (keepAlive handles ARC instead).
        // The string heuristic isReferenceReturn("W1") incorrectly retains value types.
        for reqIdx in mockableIndices {
            recorder.refReturnFlags[reqIdx] = false
        }

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
        _matcherStack = []
        recorder.activeMatchers = []
        recorder.mode = mode
        await block()
        if !_matcherStack.isEmpty {
            recorder.lastRecording?.matchers = _matcherStack
            _matcherStack = []
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the async closure")
        }
        recorder.lastRecording = nil
        return recording
    }

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
