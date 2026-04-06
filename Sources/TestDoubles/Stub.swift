#if MANUAL_STUB
// MARK: - StubConformer

/// Marks a user-written struct as a manual stub.
/// The struct provides protocol conformance by delegating each method to its ``Stub``.
///
/// ```swift
/// struct ServiceStub: ServiceProtocol, StubConformer {
///     let stub: Stub<Self>
///
///     // Approach A — @dynamicMemberLookup (sync, non-throwing)
///     func find(id: Int) -> String          { stub.find(id: id) }
///     var count: Int                          { stub.count }
///
///     // Approach B — #function default arg (throwing / async, always valid fallback)
///     func save(_ item: Item) throws        { try stub.throwingCall(item) }
///     func load() async -> [String]         { await stub.asyncCall() }
/// }
/// ```
public protocol StubConformer {
    init(stub: Stub<Self>)
}

// MARK: - Stub<T>

/// Backing type for user-written manual stubs.
///
/// Provides recording, matching, and dispatch without thunks, witness-table patching,
/// or runtime compilation. Works on all platforms, including when the protocol is
/// defined in a precompiled external module.
///
/// ```swift
/// let stub = Stub<ServiceStub>()
/// stub.when { $0.find(id: equal(42)) }.returns("Alice")
/// let sut: any ServiceProtocol = stub()
/// #expect(sut.find(id: 42) == "Alice")
/// stub.verify { $0.find(id: equal(42)) }.wasCalled()
/// ```
@dynamicMemberLookup
public class Stub<T: StubConformer>: @unchecked Sendable {
    let recorder = NamedStubRecorder()

    public init() {}

    // MARK: - Dynamic member lookup (Approach A)
    //
    // Two subscript overloads — Swift disambiguates by use site:
    //
    //   var count: Int { stub.count }       → result must be Int, not callable
    //                                          → picks subscript<R=Int>
    //
    //   func find(id: Int) -> String {        → result is called with (id:)
    //       stub.find(id: id)                 → only MethodProxy is callable
    //   }                                     → picks subscript -> MethodProxy

    /// Property access: `var count: Int { stub.count }`.
    /// `R` is inferred from the property's declared return type.
    /// Disfavored so Swift prefers ``MethodProxy`` for call sites; falls back here for properties.
    @_disfavoredOverload
    public subscript<R>(dynamicMember member: String) -> R {
        recorder.dispatch(method: member, args: [])
    }

    /// Method calls: `func find(id: Int) -> String { stub.find(id: id) }`.
    /// Returns a `@dynamicCallable` proxy that forwards labeled or unlabeled arguments.
    public subscript(dynamicMember member: String) -> MethodProxy<T> {
        MethodProxy(stub: self, method: member)
    }

    // MARK: - Explicit dispatch (Approach B)
    //
    // The `function` parameter defaults to `#function`, which is evaluated at the
    // call site — so the caller's function name is captured automatically:
    //
    //   func find(id: Int) -> String { stub.call(id) }
    //   // #function at the call site = "find(id:)"
    //
    // Use Approach B for throwing and async methods, where @dynamicCallable
    // overload selection is unreliable across Swift versions.

    /// Dispatch a synchronous method.
    /// ```swift
    /// func find(id: Int) -> String { stub.call(id) }
    /// ```
    public func call<R>(_ args: Any..., function: String = #function) -> R {
        recorder.dispatch(method: function, args: args)
    }

    /// Dispatch a throwing method.
    /// ```swift
    /// func save(_ item: Item) throws { try stub.throwingCall(item) }
    /// ```
    public func throwingCall<R>(_ args: Any..., function: String = #function) throws -> R {
        try recorder.dispatchThrowing(method: function, args: args)
    }

    /// Dispatch an async method.
    /// ```swift
    /// func load() async -> [String] { await stub.asyncCall() }
    /// ```
    public func asyncCall<R>(_ args: Any..., function: String = #function) async -> R {
        await recorder.dispatchAsync(method: function, args: args)
    }

    // Void overloads — picked by Swift when the result is discarded, avoiding
    // "generic parameter R could not be inferred" in void method bodies.

    /// Void variant: `func reset() { stub.call() }`
    public func call(_ args: Any..., function: String = #function) {
        let _: Void = recorder.dispatch(method: function, args: args)
    }

    /// Void variant: `func save(_ item: Item) throws { try stub.throwingCall(item) }`
    public func throwingCall(_ args: Any..., function: String = #function) throws {
        let _: Void = try recorder.dispatchThrowing(method: function, args: args)
    }

    /// Void variant: `func reload() async { await stub.asyncCall() }`
    public func asyncCall(_ args: Any..., function: String = #function) async {
        let _: Void = await recorder.dispatchAsync(method: function, args: args)
    }

    // MARK: - callAsFunction

    /// Returns a `T` instance backed by this stub, for use as the protocol type.
    /// ```swift
    /// let sut: any ServiceProtocol = stub()
    /// ```
    public func callAsFunction() -> T {
        T(stub: self)
    }

    // MARK: - when

    /// Register a stub for a non-void method. Chain `.returns(_:)` or `.then(_:)` to configure the response.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (T) -> R) -> NamedStubBuilder<R> {
        let recording = record { _ = call(T(stub: self)) }
        return NamedStubBuilder(recorder: recorder, recording: recording)
    }

    /// Register a stub for a throwing non-void method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (T) throws -> R) -> NamedStubBuilder<R> {
        let recording = record { _ = try! call(T(stub: self)) }
        return NamedStubBuilder(recorder: recorder, recording: recording)
    }

    /// Void method — auto-registers so no `.returns(())` is needed.
    @discardableResult
    public func when(_ call: (T) -> Void) -> NamedStubBuilder<Void> {
        let recording = record { call(T(stub: self)) }
        let matchers = resolvedMatchers(for: recording)
        recorder.addStub(method: recording.methodName, matchers: matchers, returnValue: { _ in () })
        return NamedStubBuilder(recorder: recorder, recording: recording)
    }

    /// Void throwing method — auto-registers.
    @discardableResult
    public func when(_ call: (T) throws -> Void) -> NamedStubBuilder<Void> {
        let recording = record { try! call(T(stub: self)) }
        let matchers = resolvedMatchers(for: recording)
        recorder.addStub(method: recording.methodName, matchers: matchers, returnValue: { _ in () })
        return NamedStubBuilder(recorder: recorder, recording: recording)
    }

    /// Register a stub for an async non-void method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (T) async -> R) async -> NamedStubBuilder<R> {
        let recording = await recordAsync { _ = await call(T(stub: self)) }
        return NamedStubBuilder(recorder: recorder, recording: recording)
    }

    /// Register a stub for an async throwing non-void method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (T) async throws -> R) async -> NamedStubBuilder<R> {
        let recording = await recordAsync { _ = try! await call(T(stub: self)) }
        return NamedStubBuilder(recorder: recorder, recording: recording)
    }

    // MARK: - verify

    /// Verify that a method was called. Chain `.wasCalled()` or `.withArgs(_:)` to assert.
    @discardableResult
    public func verify(_ call: (T) -> some Any) -> NamedVerifyBuilder {
        let recording = record(mode: .verifying) { _ = call(T(stub: self)) }
        return NamedVerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Verify that a throwing method was called.
    @discardableResult
    public func verify(_ call: (T) throws -> some Any) -> NamedVerifyBuilder {
        let recording = record(mode: .verifying) { _ = try! call(T(stub: self)) }
        return NamedVerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Assert that a method was called exactly `times` times.
    public func verify(called times: Int, _ call: (T) -> some Any) {
        let recording = record(mode: .verifying) { _ = call(T(stub: self)) }
        NamedVerifyBuilder(recorder: recorder, recording: recording).wasCalled(times: times)
    }

    /// Assert that a method was never called.
    public func verify(never call: (T) -> some Any) {
        verify(called: 0, call)
    }

    // MARK: - Private helpers

    private func record(mode: NamedStubRecorder.Mode = .recording, _ block: () -> Void) -> NamedRecordedCall {
        MatcherContext.begin()
        recorder.mode = mode
        block()
        let matchers = MatcherContext.end()
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("[TestDoubles] No method was called in the closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    private func recordAsync(mode: NamedStubRecorder.Mode = .recording, _ block: () async -> Void) async -> NamedRecordedCall {
        MatcherContext.begin()
        recorder.mode = mode
        await block()
        let matchers = MatcherContext.end()
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("[TestDoubles] No method was called in the async closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    private func resolvedMatchers(for recording: NamedRecordedCall) -> [ParameterMatcher] {
        recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
    }
}

// MARK: - MethodProxy

/// Internal proxy returned by ``Stub``'s method-access subscript (Approach A).
/// Forwards `@dynamicCallable` invocations into the stub's recorder.
///
/// Only `withKeywordArguments` is provided (a single overload prevents disambiguation
/// ambiguity for zero-argument calls). Positional calls also route here with empty keys.
@dynamicCallable
public struct MethodProxy<T: StubConformer> {
    let stub: Stub<T>
    let method: String

    /// Called for all method invocations: `stub.find(id: id)`, `stub.process(item, 3)`, etc.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) -> R {
        stub.recorder.dispatch(method: method, args: args.map(\.value))
    }
}

// MARK: - NamedStubBuilder

/// Configures the return value or action for a stubbed method.
/// Returned by ``Stub/when(_:)-3yepq``.
public struct NamedStubBuilder<R> {
    let recorder: NamedStubRecorder
    let recording: NamedRecordedCall

    /// Return a static value.
    /// ```swift
    /// stub.when { $0.find(id: any()) }.returns("Alice")
    /// ```
    @discardableResult
    public func returns(_ value: @autoclosure @escaping () -> R) -> Self {
        recorder.addStub(method: recording.methodName, matchers: resolvedMatchers(), returnValue: { _ in value() })
        return self
    }

    /// Return a value (or throw) based on the call arguments.
    /// ```swift
    /// stub.when { try $0.save(any()) }.then { throw SaveError() }
    /// stub.when { $0.find(id: any()) }.then { args in "id_\(args[0])" }
    /// ```
    @discardableResult
    public func then(_ handler: @escaping ([Any]) throws -> R) -> Self {
        let matchers = resolvedMatchers()
        recorder.addThrowingStub(method: recording.methodName, matchers: matchers, handler: handler)
        recorder.addStub(method: recording.methodName, matchers: matchers, returnValue: { args in try! handler(args) })
        return self
    }

    /// Convenience: no-args handler.
    @discardableResult
    public func then(_ handler: @escaping () throws -> R) -> Self {
        then { _ in try handler() }
    }

    private func resolvedMatchers() -> [ParameterMatcher] {
        recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
    }
}

// MARK: - NamedVerifyBuilder

/// Asserts that a stubbed method was called the expected number of times.
/// Returned by ``Stub/verify(_:)-7f2m3``.
public struct NamedVerifyBuilder {
    let recorder: NamedStubRecorder
    let recording: NamedRecordedCall

    /// Assert the method was called (at least once, or exactly `times` times).
    public func wasCalled(times: Int? = nil) {
        let matchers = resolvedMatchers()
        let count = recorder.callCount(method: recording.methodName, matchers: matchers)
        if let expected = times {
            precondition(count == expected,
                "'\(recording.methodName)': expected \(expected) call(s), got \(count)")
        } else {
            precondition(count > 0,
                "'\(recording.methodName)': expected at least 1 call, got 0")
        }
    }

    /// Assert the method was never called.
    public func wasNotCalled() { wasCalled(times: 0) }

    /// Inspect the arguments of all matching calls.
    public func withArgs(_ handler: ([[Any]]) -> Void) {
        let matchers = resolvedMatchers()
        let matching = recorder.calls.filter { call in
            call.methodName == recording.methodName &&
            (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }
        handler(matching.map(\.args))
    }

    private func resolvedMatchers() -> [ParameterMatcher] {
        recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
    }

    private func matchArgs(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }
}
#endif
