import Echo

extension Stub.Requirement {
    /// Describes a method requirement.
    public static func method<each Argument, Result>(
        _ arguments: repeat (each Argument).Type,
        returning result: Result.Type,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .method,
            arguments: concreteValues(repeat each arguments),
            result: concreteValue(result),
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes a synchronous method whose signature contains a function value.
    ///
    /// The noncapturing adapter must use `@convention(thin)`, repeat the
    /// protocol requirement's exact explicit argument, result, and
    /// throwing signature, then append ``Stub/Invocation`` as its final
    /// parameter. Spell `@escaping` on function-valued parameters exactly
    /// as the protocol does.
    ///
    /// ```swift
    /// let adapter: @convention(thin) (
    ///     @escaping Transform, Stub<any Transformer>.Invocation
    /// ) -> Transform = { transform, invocation in
    ///     invocation.call(transform)
    /// }
    ///
    /// .method(Transform.self, returning: Transform.self, using: adapter)
    /// ```
    public static func method<each Argument, Result, Adapter>(
        _ arguments: repeat (each Argument).Type,
        returning result: Result.Type,
        isThrowing: Bool = false,
        using adapter: Adapter
    ) -> Self {
        Self(
            kind: .method,
            arguments: concreteValues(repeat each arguments),
            result: concreteValue(result),
            isThrowing: isThrowing,
            isAsync: false,
            typedWitnessAdapterFactory: typedAdapterFactory(adapter)
        )
    }

    /// Describes a synchronous typed-throwing method whose signature contains a function value.
    ///
    /// The adapter follows the same `@convention(thin)` contract as the
    /// nonthrowing `using:` overload and must declare `throws(Failure)`.
    public static func method<each Argument, Result, Failure: Error, Adapter>(
        _ arguments: repeat (each Argument).Type,
        returning result: Result.Type,
        throwing error: Failure.Type,
        using adapter: Adapter
    ) -> Self {
        Self(
            kind: .method,
            arguments: concreteValues(repeat each arguments),
            result: concreteValue(result),
            typedErrorType: error,
            isThrowing: true,
            isAsync: false,
            typedWitnessAdapterFactory: typedAdapterFactory(adapter)
        )
    }

    /// Describes a synchronous method with a concrete typed error.
    public static func method<each Argument, Result, Failure: Error>(
        _ arguments: repeat (each Argument).Type,
        returning result: Result.Type,
        throwing error: Failure.Type
    ) -> Self {
        Self(
            kind: .method,
            arguments: concreteValues(repeat each arguments),
            result: concreteValue(result),
            typedErrorType: error,
            isThrowing: true,
            isAsync: false
        )
    }

    /// Describes an async method with a concrete typed error.
    public static func method<each Argument, Result, Failure: Error>(
        _ arguments: repeat (each Argument).Type,
        returning result: Result.Type,
        throwing error: Failure.Type,
        isAsync: Bool
    ) -> Self {
        Self(
            kind: .method,
            arguments: concreteValues(repeat each arguments),
            result: concreteValue(result),
            typedErrorType: error,
            isThrowing: true,
            isAsync: isAsync
        )
    }

    /// Describes a method containing direct associated-type values.
    public static func method(
        _ arguments: Value...,
        returning result: Value,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .method,
            arguments: arguments,
            result: result,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes a synchronous typed-throwing method containing dependent values.
    public static func method<Failure: Error>(
        _ arguments: Value...,
        returning result: Value,
        throwing error: Failure.Type
    ) -> Self {
        Self(
            kind: .method,
            arguments: arguments,
            result: result,
            typedErrorType: error,
            isThrowing: true,
            isAsync: false
        )
    }

    /// Describes a method whose typed error is a directly named associated type.
    ///
    /// The associated type's concrete binding must conform to `Error`.
    public static func method(
        _ arguments: Value...,
        returning result: Value,
        throwingAssociatedTypeNamed errorName: String,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .method,
            arguments: arguments,
            result: result,
            typedErrorAssociatedTypeName: errorName,
            isThrowing: true,
            isAsync: isAsync
        )
    }

    /// Describes an async typed-throwing method containing dependent values.
    public static func method<Failure: Error>(
        _ arguments: Value...,
        returning result: Value,
        throwing error: Failure.Type,
        isAsync: Bool
    ) -> Self {
        Self(
            kind: .method,
            arguments: arguments,
            result: result,
            typedErrorType: error,
            isThrowing: true,
            isAsync: isAsync
        )
    }

    /// Describes an initializer requirement with concrete parameters.
    ///
    /// Initializer parameters use owned transport by default, matching the
    /// protocol witness calling convention.
    public static func initializer<each Argument>(
        _ arguments: repeat (each Argument).Type,
        isFailable: Bool = false,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .initializer,
            arguments: concreteValues(repeat each arguments),
            result: Value(source: .selfType(isOptional: isFailable), ownership: nil),
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes an initializer requirement containing dependent values.
    ///
    /// The first and additional initializer parameters use owned transport
    /// by default, matching the protocol witness calling convention.
    public static func initializer(
        _ firstArgument: Value,
        _ additionalArguments: Value...,
        isFailable: Bool = false,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .initializer,
            arguments: [firstArgument] + additionalArguments,
            result: Value(source: .selfType(isOptional: isFailable), ownership: nil),
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes a property getter requirement.
    public static func getter<Concrete>(
        _ value: Concrete.Type,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .getter,
            arguments: [],
            result: concreteValue(value),
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Infers a synchronous property getter requirement from a key path.
    ///
    /// The key path supplies the concrete result type but does not identify
    /// or reorder the requirement. Use the closure overloads for effectful
    /// getters.
    public static func getter<Result>(
        signatureOf property: KeyPath<P, Result>
    ) -> Self {
        _ = property
        return inferredGetter(
            returning: Result.self,
            isThrowing: false,
            isAsync: false
        )
    }

    /// Infers a synchronous property getter requirement from an accessor closure.
    public static func getter<Result>(
        signatureOf getter: (_ instance: P) -> Result
    ) -> Self {
        _ = getter
        return inferredGetter(
            returning: Result.self,
            isThrowing: false,
            isAsync: false
        )
    }

    /// Infers a synchronous throwing property getter requirement from an accessor closure.
    public static func getter<Result, Failure: Error>(
        signatureOf getter: (_ instance: P) throws(Failure) -> Result
    ) -> Self {
        _ = getter
        let effect = inferredThrowingEffect(for: Failure.self)
        return inferredGetter(
            returning: Result.self,
            typedErrorType: effect.typedErrorType,
            isThrowing: effect.isThrowing,
            isAsync: false
        )
    }

    /// Infers an asynchronous property getter requirement from an accessor closure.
    public static func getter<Result>(
        signatureOf getter: (_ instance: P) async -> Result
    ) -> Self {
        _ = getter
        return inferredGetter(
            returning: Result.self,
            isThrowing: false,
            isAsync: true
        )
    }

    /// Infers an asynchronous throwing property getter requirement from an accessor closure.
    public static func getter<Result, Failure: Error>(
        signatureOf getter: (_ instance: P) async throws(Failure) -> Result
    ) -> Self {
        _ = getter
        let effect = inferredThrowingEffect(for: Failure.self)
        return inferredGetter(
            returning: Result.self,
            typedErrorType: effect.typedErrorType,
            isThrowing: effect.isThrowing,
            isAsync: true
        )
    }

    /// Describes a synchronous property getter whose result is a function value.
    ///
    /// The adapter must be an exact
    /// `@convention(thin) (Stub.Invocation) -> Concrete` function.
    public static func getter<Concrete, Adapter>(
        _ value: Concrete.Type,
        isThrowing: Bool = false,
        using adapter: Adapter
    ) -> Self {
        Self(
            kind: .getter,
            arguments: [],
            result: concreteValue(value),
            isThrowing: isThrowing,
            isAsync: false,
            typedWitnessAdapterFactory: typedAdapterFactory(adapter)
        )
    }

    /// Describes a getter returning a direct associated type.
    public static func getter(
        _ value: Value,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .getter,
            arguments: [],
            result: value,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes a subscript getter with concrete index and result types.
    public static func subscriptGetter<each Index, Result>(
        indexedBy indices: repeat (each Index).Type,
        returning result: Result.Type,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .getter,
            arguments: concreteValues(repeat each indices),
            result: concreteValue(result),
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes a synchronous subscript getter whose indices or result contain a function value.
    ///
    /// The thin adapter repeats the index parameters, appends
    /// ``Stub/Invocation``, and returns `Result`.
    public static func subscriptGetter<each Index, Result, Adapter>(
        indexedBy indices: repeat (each Index).Type,
        returning result: Result.Type,
        isThrowing: Bool = false,
        using adapter: Adapter
    ) -> Self {
        Self(
            kind: .getter,
            arguments: concreteValues(repeat each indices),
            result: concreteValue(result),
            isThrowing: isThrowing,
            isAsync: false,
            typedWitnessAdapterFactory: typedAdapterFactory(adapter)
        )
    }

    /// Describes a subscript getter containing dependent values.
    public static func subscriptGetter(
        indexedBy indices: Value...,
        returning result: Value,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> Self {
        Self(
            kind: .getter,
            arguments: indices,
            result: result,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// Describes a property setter requirement.
    public static func setter<Concrete>(_ value: Concrete.Type) -> Self {
        setter(concreteValue(value))
    }

    /// Infers a synchronous property setter requirement from a writable key path.
    ///
    /// The key path supplies the concrete assigned-value type but does not
    /// identify or reorder the requirement.
    public static func setter<Concrete>(
        signatureOf property: WritableKeyPath<P, Concrete>
    ) -> Self {
        _ = property
        return Self(
            kind: .setter,
            arguments: [concreteValue(Concrete.self)],
            result: concreteValue(Void.self),
            isThrowing: false,
            isAsync: false,
            inferredFromSignature: true
        )
    }

    /// Describes a property setter using a dependent value.
    public static func setter(_ value: Value) -> Self {
        Self(
            kind: .setter,
            arguments: [value],
            result: concreteValue(Void.self),
            isThrowing: false,
            isAsync: false
        )
    }

    /// Describes a subscript setter with concrete index and value types.
    ///
    /// The resulting witness signature places the assigned value before
    /// the indices, matching Swift's setter calling convention.
    public static func subscriptSetter<each Index, AssignedValue>(
        indexedBy indices: repeat (each Index).Type,
        assigning value: AssignedValue.Type
    ) -> Self {
        Self(
            kind: .setter,
            arguments: [concreteValue(value)] + concreteValues(repeat each indices),
            result: concreteValue(Void.self),
            isThrowing: false,
            isAsync: false
        )
    }

    /// Describes a subscript setter containing dependent values.
    public static func subscriptSetter(
        indexedBy indices: Value...,
        assigning value: Value
    ) -> Self {
        Self(
            kind: .setter,
            arguments: [value] + indices,
            result: concreteValue(Void.self),
            isThrowing: false,
            isAsync: false
        )
    }

    /// Collects a parameter pack of metatypes into ordinary concrete values.
    private static func concreteValues<each T>(
        _ types: repeat (each T).Type
    ) -> [Value] {
        var values: [Value] = []
        for type in repeat each types {
            values.append(concreteValue(type))
        }
        return values
    }

    private static func concreteValue(_ type: Any.Type) -> Value {
        Value(source: .concrete(type), ownership: nil)
    }

    static func inferredMethod(
        arguments: [Any.Type],
        returning result: Any.Type,
        typedErrorType: Any.Type? = nil,
        isThrowing: Bool,
        isAsync: Bool
    ) -> Self {
        Self(
            kind: .method,
            arguments: arguments.map(concreteValue),
            result: concreteValue(result),
            typedErrorType: typedErrorType,
            isThrowing: isThrowing,
            isAsync: isAsync,
            inferredFromSignature: true
        )
    }

    private static func inferredGetter<Result>(
        returning result: Result.Type,
        typedErrorType: Any.Type? = nil,
        isThrowing: Bool,
        isAsync: Bool
    ) -> Self {
        Self(
            kind: .getter,
            arguments: [],
            result: concreteValue(result),
            typedErrorType: typedErrorType,
            isThrowing: isThrowing,
            isAsync: isAsync,
            inferredFromSignature: true
        )
    }

    static func inferredThrowingEffect<Failure: Error>(
        for failure: Failure.Type
    ) -> (isThrowing: Bool, typedErrorType: Any.Type?) {
        if ObjectIdentifier(failure) == ObjectIdentifier(Never.self) {
            return (false, nil)
        }
        if ObjectIdentifier(failure) == ObjectIdentifier((any Error).self) {
            return (true, nil)
        }
        return (true, failure)
    }

    func descriptor(
        index: Int,
        witnessIndex: Int,
        receiver: StubRequirementReceiver,
        protocolDescriptor: ProtocolDescriptor,
        bindings: AssociatedTypeBindings,
        containsAssociatedTypes: Bool
    ) throws -> MethodDescriptor {
        try validateInferredSignature(
            index: index,
            protocolDescriptor: protocolDescriptor,
            containsAssociatedTypes: containsAssociatedTypes
        )
        let resolvedTypedError:
            (
                type: Any.Type?,
                dependency: WitnessValueDependency
            )
        if let name = typedErrorAssociatedTypeName {
            let binding = try bindings.binding(
                named: name,
                declaredBy: protocolDescriptor
            )
            guard binding.type is any Error.Type else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolDescriptor.name,
                    reason: "Associated typed error '\(name)' is bound to '\(runtimeTypeName(binding.type))', which does not conform to Error."
                )
            }
            resolvedTypedError = (
                binding.type,
                bindings.dependency(for: binding)
            )
        } else {
            resolvedTypedError = (typedErrorType, .independent)
        }
        return try MethodDescriptor(
            kind: kind,
            receiver: receiver,
            origin: .explicit,
            name: "requirement_\(index)",
            index: index,
            witnessIndex: witnessIndex,
            arguments: try arguments.map {
                try $0.resolve(protocolDescriptor: protocolDescriptor, bindings: bindings)
            },
            result: try result.resolve(
                protocolDescriptor: protocolDescriptor,
                bindings: bindings
            ),
            protocolName: protocolDescriptor.name,
            typedErrorType: resolvedTypedError.type,
            typedErrorDependency: resolvedTypedError.dependency,
            selfIsClassConstrained: protocolUsesClassSelfConvention(
                protocolDescriptor
            ),
            isThrowing: isThrowing,
            isAsync: isAsync,
            typedWitnessAdapterFactory: typedWitnessAdapterFactory
        )
    }

    private func validateInferredSignature(
        index: Int,
        protocolDescriptor: ProtocolDescriptor,
        containsAssociatedTypes: Bool
    ) throws {
        guard inferredFromSignature else { return }
        if containsAssociatedTypes {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(index) uses `signatureOf:` in an existential containing associated types. Function conversion erases associated-type identity; describe this requirement with explicit `Requirement.Value` values."
            )
        }

        let values = arguments + [result]
        let containsErasedSelf = values.contains { value in
            guard case .concrete(let type) = value.source else { return false }
            return ObjectIdentifier(type) == ObjectIdentifier(P.self)
                || ObjectIdentifier(type) == ObjectIdentifier(Optional<P>.self)
        }
        if containsErasedSelf {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(index) uses `signatureOf:` with a protocol-existential "
                    + "value that may represent dynamic `Self`. Function conversion erases "
                    + "that distinction; describe this requirement with explicit "
                    + "`Requirement.Value` values."
            )
        }

        if typedErrorType != nil || typedErrorAssociatedTypeName != nil,
            kind != .method
        {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(index) uses `signatureOf:` with typed throws on an accessor. Typed-throwing accessors are unsupported."
            )
        }
    }
}
