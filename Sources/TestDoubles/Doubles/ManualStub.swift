/// Marks a hand-written struct as a manually stubbed conformer.
///
/// Conform your stub struct to both your protocol and
/// `ManualStubConformer`, and
/// forward each requirement to a `CompiledStub<Self>`:
///
/// ```swift
/// struct MyServiceStub: MyService, ManualStubConformer {
///     let stub: CompiledStub<Self>
///     func fetch(id: Int) -> String { stub.requirements.fetch(id: id) }
///     func reset() { stub.requirements.reset() }
/// }
/// ```
///
/// The synthesized memberwise initializer satisfies `init(stub:)` for free.
public protocol ManualStubConformer {
    /// Creates a conformer backed by `stub`.
    ///
    /// Most stub structs satisfy this requirement with a synthesized
    /// memberwise initializer for a stored `let stub: CompiledStub<Self>`.
    init(stub: CompiledStub<Self>)
}

/// A manual stub conformer that can be erased to its protocol existential.
///
/// Generated conformers use this refinement to expose
/// ``CompiledStub/automatic()`` without generating a constrained extension.
/// The generated erasure witness is compiled in the same source context as
/// the protocol conformance, so Swift selects the correct existential
/// representation.
public protocol AutomaticStubConformer: ManualStubConformer {
    /// The protocol existential represented by this conformer.
    associatedtype StubbedProtocol

    /// Compiler-emitted evidence for runtime construction and compiled fallback.
    ///
    /// Existing hand-written conformers receive a source-compatible default
    /// that preserves runtime discovery before using their compiled fallback.
    static var compilerEvidence: StubCompilerEvidence<StubbedProtocol> { get }

    /// Erases a compiled conformer to its protocol existential.
    ///
    /// - Parameter conformer: The compiler-backed conformer to erase.
    /// - Returns: The conformer represented as ``StubbedProtocol``.
    static func eraseToStubbedProtocol(_ conformer: Self) -> StubbedProtocol
}

extension AutomaticStubConformer {
    /// Default evidence for a hand-written conformer that relies on runtime discovery.
    public static var compilerEvidence: StubCompilerEvidence<StubbedProtocol> {
        StubCompilerEvidence(
            runtimeConstruction: .automaticDiscovery,
            compiledFallbackEligibility: .compiledConformer,
            sourceSupport: StubSourceSupportReport(
                protocolName: String(reflecting: StubbedProtocol.self),
                isComplete: false,
                requirements: []
            )
        )
    }
}

/// An explicitly constructed test double backed by the shared recording and
/// behavior engine.
///
/// Unlike ``Stub``, `CompiledStub` never introspects a witness table or generates
/// executable code. A ``ManualStubConformer`` can forward protocol
/// requirements explicitly, while ``ClientStub`` constructs closure-field
/// dependency values through ``ClientStubEndpoints``. Both paths use the same
/// matching, verification, and diagnostic behavior as ``Stub``.
///
/// ```swift
/// let stub = CompiledStub<MyServiceStub>()
/// stub.when { $0.fetch(id: Match.equal(42)) }.thenReturn("Alice")
///
/// let service: any MyService = stub()
/// // service.fetch(id: 42) == "Alice"
/// ```
@dynamicMemberLookup
public final class CompiledStub<T>: @unchecked Sendable {
    let recorder: StubRecorder
    private let materializer: (CompiledStub<T>) -> T

    init(
        materializing materializer: @escaping (CompiledStub<T>) -> T,
        allowsForwardingFallback: Bool = false
    ) {
        recorder = StubRecorder(
            methods: [],
            allowsForwardingFallback: allowsForwardingFallback
        )
        self.materializer = materializer
        if let session = TestDoubleTestingContext.session {
            session.register(recorder)
            session.registerLifetime(of: recorder) { [weak self] in
                self != nil
            }
        }
    }

    /// Returns a `T` backed by this stub, for use as the protocol type.
    /// ```swift
    /// let service: any MyService = stub()
    /// ```
    public func callAsFunction() -> T {
        materialize()
    }

    /// Assigns a name used in automatic test-double teardown diagnostics.
    ///
    /// ```swift
    /// let service = CompiledStub<MyServiceStub>().named("service")
    /// ```
    @discardableResult
    public func named(_ name: String) -> Self {
        recorder.nameTestDouble(name)
        return self
    }

    func materializeForRecording() -> T {
        materialize()
    }

    private func materialize() -> T {
        materializer(self)
    }

    // MARK: - Requirement routes

    /// A collision-free namespace for forwarding non-throwing requirements.
    ///
    /// Use this route from hand-written conformers so requirement names never
    /// collide with `CompiledStub`'s configuration and verification API:
    ///
    /// ```swift
    /// func reset() { stub.requirements.reset() }
    /// var count: Int { stub.requirements.count }
    /// ```
    public var requirements: ManualRequirementRoute<T> {
        ManualRequirementRoute(stub: self)
    }

    /// A collision-free namespace for forwarding throwing requirements.
    ///
    /// ```swift
    /// func save(_ item: Item) throws {
    ///     try stub.throwingRequirements.save(item)
    /// }
    /// ```
    public var throwingRequirements: ManualThrowingRequirementRoute<T> {
        ManualThrowingRequirementRoute(stub: self)
    }

    /// Forwards a non-throwing method through dynamic-member syntax.
    ///
    /// ```swift
    /// func fetch(id: Int) -> String { stub.fetch(id: id) }
    /// ```
    @_documentation(visibility: internal)
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
    /// Disfavored so Swift prefers method forwarding at call sites.
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

    // MARK: - Compatibility route

    /// Routes throwing methods and throwing getters, which can't share a
    /// dynamic-member subscript with their non-throwing counterparts —
    /// Swift does not allow overloading a subscript getter purely on
    /// `throws`.
    /// ```swift
    /// func save(_ item: Item) throws {
    ///     try stub.throwingRequirements.save(item)
    /// }
    /// var token: String {
    ///     get throws { try stub.throwingRequirements.token }
    /// }
    /// ```
    public var throwing: ManualThrowingRequirementRoute<T> {
        ManualThrowingRequirementRoute(stub: self)
    }

    // MARK: - Explicit fallback methods
    //
    // Always available, and the only way to reach async property getters:
    // Swift does not allow overloading a subscript getter purely on `async`
    // either, so the dynamic-member routes above can't reach that shape.
    // `function` defaults to `#function`, evaluated at the call site, so the
    // forwarding body doesn't retype the requirement's name.

    /// Forwards a synchronous non-throwing requirement through its `#function`
    /// key and the static types of its arguments.
    ///
    /// Use this fallback when dynamic-member forwarding cannot express the
    /// requirement shape.
    public func call<each Argument, R>(
        _ args: repeat each Argument,
        function: String = #function
    ) -> R {
        let packed = manualPackedArguments(repeat each args)
        return dispatchMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Void variant of `call(_:function:)`.
    public func call<each Argument>(
        _ args: repeat each Argument,
        function: String = #function
    ) {
        let packed = manualPackedArguments(repeat each args)
        let _: Void = dispatchMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Asynchronous variant of `call(_:function:)`.
    public func call<each Argument, R>(
        _ args: repeat each Argument,
        function: String = #function
    ) async -> R {
        let packed = manualPackedArguments(repeat each args)
        return await dispatchAsyncMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Asynchronous `Void` variant of `call(_:function:)`.
    public func call<each Argument>(
        _ args: repeat each Argument,
        function: String = #function
    ) async {
        let packed = manualPackedArguments(repeat each args)
        let _: Void = await dispatchAsyncMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Forwards a synchronous throwing requirement through its `#function`
    /// key and the static types of its arguments.
    public func throwingCall<each Argument, R>(
        _ args: repeat each Argument,
        function: String = #function
    ) throws -> R {
        let packed = manualPackedArguments(repeat each args)
        return try dispatchThrowingMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Typed-throws variant of `throwingCall(_:function:)`.
    ///
    /// The configured handler must throw `Failure`; any other error fails
    /// closed with an expected/actual type diagnostic.
    public func throwingCall<each Argument, R, Failure: Error>(
        _ args: repeat each Argument,
        throwing failureType: Failure.Type,
        function: String = #function
    ) throws(Failure) -> R {
        let packed = manualPackedArguments(repeat each args)
        return try dispatchThrowingMethod(
            route: packed.route(for: function),
            args: packed.values,
            throwing: failureType
        )
    }

    /// Void variant of `throwingCall(_:function:)`.
    public func throwingCall<each Argument>(
        _ args: repeat each Argument,
        function: String = #function
    ) throws {
        let packed = manualPackedArguments(repeat each args)
        let _: Void = try dispatchThrowingMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Void typed-throws variant of `throwingCall(_:function:)`.
    public func throwingCall<each Argument, Failure: Error>(
        _ args: repeat each Argument,
        throwing failureType: Failure.Type,
        function: String = #function
    ) throws(Failure) {
        let packed = manualPackedArguments(repeat each args)
        let _: Void = try dispatchThrowingMethod(
            route: packed.route(for: function),
            args: packed.values,
            throwing: failureType
        )
    }

    /// Asynchronous throwing variant of `throwingCall(_:function:)`.
    public func throwingCall<each Argument, R>(
        _ args: repeat each Argument,
        function: String = #function
    ) async throws -> R {
        let packed = manualPackedArguments(repeat each args)
        return try await dispatchAsyncThrowingMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Asynchronous typed-throws variant of `throwingCall(_:function:)`.
    public func throwingCall<each Argument, R, Failure: Error>(
        _ args: repeat each Argument,
        throwing failureType: Failure.Type,
        function: String = #function
    ) async throws(Failure) -> R {
        let packed = manualPackedArguments(repeat each args)
        return try await dispatchAsyncThrowingMethod(
            route: packed.route(for: function),
            args: packed.values,
            throwing: failureType
        )
    }

    /// Asynchronous throwing `Void` variant of `throwingCall(_:function:)`.
    public func throwingCall<each Argument>(
        _ args: repeat each Argument,
        function: String = #function
    ) async throws {
        let packed = manualPackedArguments(repeat each args)
        let _: Void = try await dispatchAsyncThrowingMethod(
            route: packed.route(for: function),
            args: packed.values
        )
    }

    /// Asynchronous typed-throws `Void` variant of
    /// `throwingCall(_:function:)`.
    public func throwingCall<each Argument, Failure: Error>(
        _ args: repeat each Argument,
        throwing failureType: Failure.Type,
        function: String = #function
    ) async throws(Failure) {
        let packed = manualPackedArguments(repeat each args)
        let _: Void = try await dispatchAsyncThrowingMethod(
            route: packed.route(for: function),
            args: packed.values,
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
                forwardingMethod: "throwingCall"
            )
        }
    }

    func internMethod(
        route: ManualMethodRouteIdentity,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> ManualMethod {
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

    func dispatchValue<R>(method: ManualMethod, args: [Any]) -> R {
        do {
            return try dispatchThrowingValue(method: method, args: args)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing stub handler for '\(method.name)' threw \(error). "
                    + "Forward this requirement through `stub.throwingRequirements` instead."
            )
        }
    }

    func dispatchThrowingValue<R>(method: ManualMethod, args: [Any]) throws -> R {
        try recorder.dispatchTyped(manualMethod: method, args: args, as: R.self)
    }

    func dispatchAsyncValue<R>(method: ManualMethod, args: [Any]) async -> R {
        do {
            return try await dispatchAsyncThrowingValue(method: method, args: args)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing async stub handler for '\(method.name)' threw \(error). "
                    + "Forward this requirement through `stub.throwingRequirements` instead."
            )
        }
    }

    func dispatchAsyncThrowingValue<R>(method: ManualMethod, args: [Any]) async throws -> R {
        switch recorder.prepareAsyncDispatch(manualMethod: method, args: args) {
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
                    "[TestDoubles] CompiledStub cannot dispatch a forwarding Spy fallback."
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
            "[TestDoubles] Typed CompiledStub handler error mismatch for '\(method)': "
                + "expected \(expected), got \(type(of: actual)). Configure a \(expected) "
                + "error or use the untyped `\(forwardingMethod)` overload."
        )
    }
}

/// Compatibility spelling for ``CompiledStub``.
public typealias ManualStub<T> = CompiledStub<T>

extension CompiledStub where T: ManualStubConformer {
    /// Creates an empty manual stub backed by `T.init(stub:)`.
    ///
    /// No requirements are validated up front. Each requirement is discovered
    /// the first time the conformer forwards to it.
    public convenience init() {
        self.init(materializing: { T(stub: $0) })
    }
}

extension CompiledStub where T: AutomaticStubConformer {
    /// Compiler-emitted construction and source-support evidence for this stub.
    ///
    /// Generated aliases expose this directly, for example
    /// `WeatherServiceStub.compilerEvidence.sourceSupport`.
    public static var compilerEvidence: StubCompilerEvidence<T.StubbedProtocol> {
        T.compilerEvidence
    }

    /// Creates an evidence-routed stub with this compiled conformer as fallback.
    ///
    /// Compiler evidence selects explicit runtime requirements, validated
    /// discovery, or an immediate compiled fallback. When an eligible runtime
    /// attempt fails, the compiler-generated erasure witness constructs `T`
    /// through ``CompiledStub`` instead.
    public static func automatic() -> Stub<T.StubbedProtocol> {
        Stub(
            fallingBackTo: T.self,
            erasingWith: T.eraseToStubbedProtocol,
            compilerEvidence: T.compilerEvidence
        )
    }
}
