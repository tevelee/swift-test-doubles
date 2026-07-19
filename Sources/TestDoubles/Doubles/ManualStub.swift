/// Marks a hand-written struct as a manually stubbed conformer.
///
/// Conform your stub struct to both your protocol and `StubConformer`, and
/// forward each requirement to a `ManualStub<Self>`:
///
/// ```swift
/// struct MyServiceStub: MyService, StubConformer {
///     let stub: ManualStub<Self>
///     func fetch(id: Int) -> String { stub.fetch(id: id) }
///     func reset() { stub.reset() }
/// }
/// ```
///
/// The synthesized memberwise initializer satisfies `init(stub:)` for free.
public protocol StubConformer {
    /// Creates a conformer backed by `stub`.
    ///
    /// Most stub structs satisfy this requirement with a synthesized
    /// memberwise initializer for a stored `let stub: ManualStub<Self>`.
    init(stub: ManualStub<Self>)
}

/// A hand-written test double for a protocol that ``Stub`` can't represent —
/// new language features, requirement shapes the runtime trampoline doesn't
/// cover, or platforms the runtime strategy doesn't run on.
///
/// Unlike ``Stub``, `ManualStub` never introspects a witness table or
/// generates executable code: your conformer struct forwards each
/// requirement explicitly, and `ManualStub` supplies the same matching,
/// verification, and diagnostic behavior ``Stub`` uses internally.
///
/// ```swift
/// let stub = ManualStub<MyServiceStub>()
/// stub.when { $0.fetch(id: equal(42)) }.thenReturn("Alice")
///
/// let service: any MyService = stub()
/// // service.fetch(id: 42) == "Alice"
/// ```
@dynamicMemberLookup
public final class ManualStub<T: StubConformer> {
    let recorder = StubRecorder(methods: [])

    /// Creates an empty manual stub. No requirements are validated up
    /// front — every requirement is discovered the first time your
    /// conformer forwards to it.
    public init() {}

    /// Returns a `T` backed by this stub, for use as the protocol type.
    /// ```swift
    /// let service: any MyService = stub()
    /// ```
    public func callAsFunction() -> T {
        materialize()
    }

    func materializeForRecording() -> T {
        materialize()
    }

    private func materialize() -> T {
        T(stub: self)
    }

    // MARK: - Base route (non-throwing methods, sync and async; getters; setters)

    /// Forwards a non-throwing method through dynamic-member syntax.
    ///
    /// ```swift
    /// func fetch(id: Int) -> String { stub.fetch(id: id) }
    /// ```
    public subscript(dynamicMember member: String) -> ManualMethodProxy<T> {
        ManualMethodProxy(stub: self, name: member)
    }

    /// Forwards a non-throwing property getter or direct setter.
    ///
    /// ```swift
    /// var count: Int { stub.count }
    /// var name: String {
    ///     get { stub.name }
    ///     set { stub.name = newValue }
    /// }
    /// ```
    ///
    /// Disfavored so Swift prefers ``ManualMethodProxy`` at call sites.
    @_disfavoredOverload
    public subscript<R>(dynamicMember member: String) -> R {
        get {
            let method = recorder.internManualMethod(
                signature: member,
                kind: .getter,
                returnType: R.self,
                isAsync: false,
                isThrowing: false
            )
            return dispatchValue(method: method, args: [])
        }
        set {
            // A distinct key from the getter's: they'd otherwise collide on
            // the recorder's shared `storedStubs[index]` entry, letting a
            // getter registration answer a setter dispatch (or vice versa)
            // with the wrong type.
            let method = recorder.internManualMethod(
                signature: "\(member)=",
                kind: .setter,
                returnType: Void.self,
                isAsync: false,
                isThrowing: false
            )
            let _: Void = dispatchValue(method: method, args: [newValue])
        }
    }

    // MARK: - `.throwing` route (sync/async-throwing methods; throwing getters)

    /// Routes throwing methods and throwing getters, which can't share a
    /// dynamic-member subscript with their non-throwing counterparts —
    /// Swift does not allow overloading a subscript getter purely on
    /// `throws`.
    /// ```swift
    /// func save(_ item: Item) throws { try stub.throwing.save(item) }
    /// var token: String { get throws { try stub.throwing.token } }
    /// ```
    public var throwing: ManualThrowingRoute<T> { ManualThrowingRoute(stub: self) }

    // MARK: - Explicit fallback methods
    //
    // Always available, and the only way to reach async property getters:
    // Swift does not allow overloading a subscript getter purely on `async`
    // either, so the dynamic-member routes above can't reach that shape.
    // `function` defaults to `#function`, evaluated at the call site, so the
    // forwarding body doesn't retype the requirement's name.

    /// Forwards a synchronous non-throwing requirement through its `#function`
    /// key.
    ///
    /// Use this fallback when dynamic-member forwarding cannot express the
    /// requirement shape.
    public func call<R>(_ args: Any..., function: String = #function) -> R {
        dispatchMethod(key: function, args: args)
    }

    /// Void variant of `call(_:function:)`.
    public func call(_ args: Any..., function: String = #function) {
        let _: Void = dispatchMethod(key: function, args: args)
    }

    /// Typed-route variant of `call(_:function:)` for overloads whose
    /// argument labels, result, and effects are otherwise identical.
    public func call<R>(_ args: Any..., route: ManualRouteID) -> R {
        dispatchMethod(route: .typed(route), args: args)
    }

    /// Void typed-route variant of `call(_:function:)`.
    public func call(_ args: Any..., route: ManualRouteID) {
        let _: Void = dispatchMethod(route: .typed(route), args: args)
    }

    /// Forwards a synchronous throwing requirement through its `#function` key.
    public func throwingCall<R>(_ args: Any..., function: String = #function) throws -> R {
        try dispatchThrowingMethod(key: function, args: args)
    }

    /// Typed-throws variant of `throwingCall(_:function:)`.
    ///
    /// The configured handler must throw `Failure`; any other error fails
    /// closed with an expected/actual type diagnostic.
    public func throwingCall<R, Failure: Error>(
        _ args: Any...,
        throwing failureType: Failure.Type,
        function: String = #function
    ) throws(Failure) -> R {
        try dispatchThrowingMethod(
            key: function,
            args: args,
            throwing: failureType
        )
    }

    /// Void variant of `throwingCall(_:function:)`.
    public func throwingCall(_ args: Any..., function: String = #function) throws {
        let _: Void = try dispatchThrowingMethod(key: function, args: args)
    }

    /// Void typed-throws variant of `throwingCall(_:function:)`.
    public func throwingCall<Failure: Error>(
        _ args: Any...,
        throwing failureType: Failure.Type,
        function: String = #function
    ) throws(Failure) {
        let _: Void = try dispatchThrowingMethod(
            key: function,
            args: args,
            throwing: failureType
        )
    }

    /// Typed-route variant of `throwingCall(_:function:)` for overloads whose
    /// argument labels, result, and effects are otherwise identical.
    public func throwingCall<R>(_ args: Any..., route: ManualRouteID) throws -> R {
        try dispatchThrowingMethod(route: .typed(route), args: args)
    }

    /// Typed-throws variant of `throwingCall(_:route:)`.
    public func throwingCall<R, Failure: Error>(
        _ args: Any...,
        route: ManualRouteID,
        throwing failureType: Failure.Type
    ) throws(Failure) -> R {
        try dispatchThrowingMethod(
            route: .typed(route),
            args: args,
            throwing: failureType
        )
    }

    /// Void typed-route variant of `throwingCall(_:function:)`.
    public func throwingCall(_ args: Any..., route: ManualRouteID) throws {
        let _: Void = try dispatchThrowingMethod(route: .typed(route), args: args)
    }

    /// Void typed-throws variant of `throwingCall(_:route:)`.
    public func throwingCall<Failure: Error>(
        _ args: Any...,
        route: ManualRouteID,
        throwing failureType: Failure.Type
    ) throws(Failure) {
        let _: Void = try dispatchThrowingMethod(
            route: .typed(route),
            args: args,
            throwing: failureType
        )
    }

    /// Forwards an asynchronous non-throwing requirement through its
    /// `#function` key.
    public func asyncCall<R>(_ args: Any..., function: String = #function) async -> R {
        await dispatchAsyncMethod(key: function, args: args)
    }

    /// Void variant of `asyncCall(_:function:)`.
    public func asyncCall(_ args: Any..., function: String = #function) async {
        let _: Void = await dispatchAsyncMethod(key: function, args: args)
    }

    /// Typed-route variant of `asyncCall(_:function:)` for overloads whose
    /// argument labels, result, and effects are otherwise identical.
    public func asyncCall<R>(_ args: Any..., route: ManualRouteID) async -> R {
        await dispatchAsyncMethod(route: .typed(route), args: args)
    }

    /// Void typed-route variant of `asyncCall(_:function:)`.
    public func asyncCall(_ args: Any..., route: ManualRouteID) async {
        let _: Void = await dispatchAsyncMethod(route: .typed(route), args: args)
    }

    /// Forwards an asynchronous throwing requirement through its `#function`
    /// key.
    public func asyncThrowingCall<R>(_ args: Any..., function: String = #function) async throws -> R {
        try await dispatchAsyncThrowingMethod(key: function, args: args)
    }

    /// Typed-throws variant of `asyncThrowingCall(_:function:)`.
    ///
    /// The configured handler must throw `Failure`; any other error fails
    /// closed with an expected/actual type diagnostic.
    public func asyncThrowingCall<R, Failure: Error>(
        _ args: Any...,
        throwing failureType: Failure.Type,
        function: String = #function
    ) async throws(Failure) -> R {
        try await dispatchAsyncThrowingMethod(
            key: function,
            args: args,
            throwing: failureType
        )
    }

    /// Void variant of `asyncThrowingCall(_:function:)`.
    public func asyncThrowingCall(_ args: Any..., function: String = #function) async throws {
        let _: Void = try await dispatchAsyncThrowingMethod(key: function, args: args)
    }

    /// Void typed-throws variant of `asyncThrowingCall(_:function:)`.
    public func asyncThrowingCall<Failure: Error>(
        _ args: Any...,
        throwing failureType: Failure.Type,
        function: String = #function
    ) async throws(Failure) {
        let _: Void = try await dispatchAsyncThrowingMethod(
            key: function,
            args: args,
            throwing: failureType
        )
    }

    /// Typed-route variant of `asyncThrowingCall(_:function:)` for overloads
    /// whose argument labels, result, and effects are otherwise identical.
    public func asyncThrowingCall<R>(_ args: Any..., route: ManualRouteID) async throws -> R {
        try await dispatchAsyncThrowingMethod(route: .typed(route), args: args)
    }

    /// Typed-throws variant of `asyncThrowingCall(_:route:)`.
    public func asyncThrowingCall<R, Failure: Error>(
        _ args: Any...,
        route: ManualRouteID,
        throwing failureType: Failure.Type
    ) async throws(Failure) -> R {
        try await dispatchAsyncThrowingMethod(
            route: .typed(route),
            args: args,
            throwing: failureType
        )
    }

    /// Void typed-route variant of `asyncThrowingCall(_:function:)`.
    public func asyncThrowingCall(_ args: Any..., route: ManualRouteID) async throws {
        let _: Void = try await dispatchAsyncThrowingMethod(route: .typed(route), args: args)
    }

    /// Void typed-throws variant of `asyncThrowingCall(_:route:)`.
    public func asyncThrowingCall<Failure: Error>(
        _ args: Any...,
        route: ManualRouteID,
        throwing failureType: Failure.Type
    ) async throws(Failure) {
        let _: Void = try await dispatchAsyncThrowingMethod(
            route: .typed(route),
            args: args,
            throwing: failureType
        )
    }

    // MARK: - Method interning + dispatch
    //
    // One helper per effect combination, shared by the explicit fallback
    // methods above and the `@dynamicCallable` proxies.

    func dispatchMethod<R>(key: String, args: [Any]) -> R {
        dispatchMethod(route: .implicit(key), args: args)
    }

    func dispatchMethod<R>(route: ManualMethodRouteIdentity, args: [Any]) -> R {
        dispatchValue(
            method: internMethod(
                route: route,
                returnType: R.self,
                isAsync: false,
                isThrowing: false
            ),
            args: args
        )
    }

    func dispatchThrowingMethod<R>(key: String, args: [Any]) throws -> R {
        try dispatchThrowingMethod(route: .implicit(key), args: args)
    }

    func dispatchThrowingMethod<R>(route: ManualMethodRouteIdentity, args: [Any]) throws -> R {
        try dispatchThrowingValue(
            method: internMethod(
                route: route,
                returnType: R.self,
                isAsync: false,
                isThrowing: true
            ),
            args: args
        )
    }

    func dispatchThrowingMethod<R, Failure: Error>(
        key: String,
        args: [Any],
        throwing failureType: Failure.Type
    ) throws(Failure) -> R {
        try dispatchThrowingMethod(
            route: .implicit(key),
            args: args,
            throwing: failureType
        )
    }

    func dispatchThrowingMethod<R, Failure: Error>(
        route: ManualMethodRouteIdentity,
        args: [Any],
        throwing failureType: Failure.Type
    ) throws(Failure) -> R {
        let method = internMethod(
            route: route,
            returnType: R.self,
            isAsync: false,
            isThrowing: true
        )
        do {
            return try dispatchThrowingValue(method: method, args: args)
        } catch let failure as Failure {
            throw failure
        } catch {
            failTypedErrorMismatch(
                method: method.name,
                expected: failureType,
                actual: error,
                forwardingMethod: "throwingCall"
            )
        }
    }

    func dispatchAsyncMethod<R>(key: String, args: [Any]) async -> R {
        await dispatchAsyncMethod(route: .implicit(key), args: args)
    }

    func dispatchAsyncMethod<R>(route: ManualMethodRouteIdentity, args: [Any]) async -> R {
        await dispatchAsyncValue(
            method: internMethod(
                route: route,
                returnType: R.self,
                isAsync: true,
                isThrowing: false
            ),
            args: args
        )
    }

    func dispatchAsyncThrowingMethod<R>(key: String, args: [Any]) async throws -> R {
        try await dispatchAsyncThrowingMethod(route: .implicit(key), args: args)
    }

    func dispatchAsyncThrowingMethod<R>(route: ManualMethodRouteIdentity, args: [Any]) async throws -> R {
        try await dispatchAsyncThrowingValue(
            method: internMethod(
                route: route,
                returnType: R.self,
                isAsync: true,
                isThrowing: true
            ),
            args: args
        )
    }

    func dispatchAsyncThrowingMethod<R, Failure: Error>(
        key: String,
        args: [Any],
        throwing failureType: Failure.Type
    ) async throws(Failure) -> R {
        try await dispatchAsyncThrowingMethod(
            route: .implicit(key),
            args: args,
            throwing: failureType
        )
    }

    func dispatchAsyncThrowingMethod<R, Failure: Error>(
        route: ManualMethodRouteIdentity,
        args: [Any],
        throwing failureType: Failure.Type
    ) async throws(Failure) -> R {
        let method = internMethod(
            route: route,
            returnType: R.self,
            isAsync: true,
            isThrowing: true
        )
        do {
            return try await dispatchAsyncThrowingValue(
                method: method,
                args: args
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            failTypedErrorMismatch(
                method: method.name,
                expected: failureType,
                actual: error,
                forwardingMethod: "asyncThrowingCall"
            )
        }
    }

    private func internMethod(
        route: ManualMethodRouteIdentity,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> MethodDescriptor {
        recorder.internManualMethod(
            route: route,
            kind: .method,
            returnType: returnType,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
    }

    // MARK: - Dispatch
    //
    // The nonthrowing variants delegate and turn any thrown error into a
    // diagnostic trap. Typed capture dispatch and placeholder resolution are
    // shared with `Stub.Invocation` through the recorder.

    func dispatchValue<R>(method: MethodDescriptor, args: [Any]) -> R {
        do {
            return try dispatchThrowingValue(method: method, args: args)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing stub handler for '\(method.name)' threw \(error). " + "Forward this requirement through `stub.throwing` instead."
            )
        }
    }

    func dispatchThrowingValue<R>(method: MethodDescriptor, args: [Any]) throws -> R {
        try recorder.dispatchTyped(method: method, args: args, as: R.self)
    }

    func dispatchAsyncValue<R>(method: MethodDescriptor, args: [Any]) async -> R {
        do {
            return try await dispatchAsyncThrowingValue(method: method, args: args)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing async stub handler for '\(method.name)' threw \(error). " + "Forward this requirement through `stub.throwing` instead."
            )
        }
    }

    func dispatchAsyncThrowingValue<R>(method: MethodDescriptor, args: [Any]) async throws -> R {
        switch recorder.prepareAsyncDispatch(method: method, args: args) {
            case .placeholder:
                return RecordingReturnPlaceholderContext.requiredValue(
                    for: R.self,
                    method: method.name
                )
            case .immediate(.success(let result)):
                return requireStubbedResult(result, as: R.self, method: method.name)
            case .immediate(.failure(let error)):
                throw error
            case .suspending(let handler):
                return requireStubbedResult(
                    try await handler(args),
                    as: R.self,
                    method: method.name
                )
            case .forwarding:
                preconditionFailure(
                    "[TestDoubles] ManualStub cannot dispatch a forwarding Spy fallback."
                )
        }
    }

    private func failTypedErrorMismatch<Failure: Error>(
        method: String,
        expected: Failure.Type,
        actual: any Error,
        forwardingMethod: String
    ) -> Never {
        fatalError(
            "[TestDoubles] Typed ManualStub handler error mismatch for '\(method)': "
                + "expected \(expected), got \(type(of: actual)). Configure a \(expected) "
                + "error or use the untyped `\(forwardingMethod)` overload."
        )
    }
}
