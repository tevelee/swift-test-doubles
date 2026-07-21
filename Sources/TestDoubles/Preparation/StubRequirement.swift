import Echo

extension Stub {
    /// The throwing behavior of a getter used with automatic signature discovery.
    ///
    /// Swift protocol descriptors identify async getters but omit whether a
    /// getter throws. Supplying this hint keeps automatic discovery for the
    /// getter's receiver, value type, associated-type dependencies, and async
    /// behavior while making its throwing convention explicit.
    public enum GetterEffect: Sendable {
        /// The getter cannot throw.
        case nonthrowing
        /// The getter uses Swift's ordinary untyped throwing convention.
        case throwing

        var isThrowing: Bool {
            switch self {
                case .nonthrowing: false
                case .throwing: true
            }
        }
    }

    /// Getter-effect hints declared by one protocol in an inheritance graph or composition.
    ///
    /// Create groups with `effects(declaredBy:_:)` and pass them to the grouped
    /// Stub initializer. Group order does not matter; effects inside a group
    /// remain in getter declaration order and skip non-getter requirements.
    public struct ProtocolGetterEffects: Sendable {
        let protocolType: Any.Type
        let effects: [GetterEffect]

        /// Groups getter effects by the protocol that directly declares them.
        ///
        /// Inherited getters belong to the protocol where they were originally
        /// declared, and a shared base protocol is grouped once.
        public static func effects(
            declaredBy protocolType: Any.Type,
            _ firstEffect: GetterEffect,
            _ additionalEffects: GetterEffect...
        ) -> Self {
            Self(
                protocolType: protocolType,
                effects: [firstEffect] + additionalEffects
            )
        }
    }

    /// Explicitly describes one protocol requirement.
    ///
    /// Requirements must be supplied base-first in depth-first declaration
    /// order. A requirement inherited along multiple paths is supplied once,
    /// at its first occurrence. Use explicit requirements when automatic
    /// discovery is unavailable or an effectful getter needs its throwing
    /// behavior stated explicitly.
    ///
    /// Source-less factories describe ABI details without referencing a
    /// protocol declaration. The caller must keep their order, value types,
    /// ownership, and effects exactly synchronized with that declaration. Prefer
    /// the `signatureOf:` factories whenever they can express the requirement.
    ///
    /// - Warning: When no linked or resilient signature source can validate a
    ///   source-less schema, a mismatch can violate the witness ABI and cause
    ///   undefined behavior when the generated value is invoked.
    public struct Requirement: Sendable {
        /// A direct concrete or associated-type value in a requirement.
        public struct Value: Sendable {
            indirect enum Source: Sendable {
                case concrete(Any.Type)
                case associatedType(String)
                case optional(Source)
                case array(Source)
                case set(Source)
                case dictionary(key: Source, value: Source)
                case selfType(isOptional: Bool)
            }
            let source: Source
            let ownership: WitnessArgumentOwnership?

            /// Describes an ordinary concrete value.
            public static func concrete<T>(_ type: T.Type) -> Self {
                Self(source: .concrete(type), ownership: nil)
            }

            /// Describes the dynamic `Self` result of a method or getter.
            ///
            /// Dynamic `Self` is supported only as a direct result. Complete
            /// the recorded
            /// ``Stub/when(returningSelf:)->StubSelfResultBuilder`` invocation
            /// with ``StubSelfResultBuilder/thenReturnValue()`` so the runtime
            /// creates a fresh value backed by this stub's resources.
            public static var dynamicSelf: Self {
                Self(source: .selfType(isOptional: false), ownership: nil)
            }

            /// Describes an optional dynamic `Self` result of a method or getter.
            ///
            /// Complete the recorded
            /// ``Stub/when(returningOptionalSelf:)->StubOptionalSelfResultBuilder``
            /// invocation with ``StubOptionalSelfResultBuilder/thenReturnValue()``,
            /// ``StubOptionalSelfResultBuilder/thenReturnNil()``, or a typed
            /// handler that returns ``StubOptionalSelfResultBuilder/Outcome``.
            public static var optionalDynamicSelf: Self {
                Self(source: .selfType(isOptional: true), ownership: nil)
            }

            /// Describes a direct occurrence of the named associated type.
            public static func associatedType(named name: String) -> Self {
                Self(source: .associatedType(name), ownership: nil)
            }

            /// Describes an optional containing the named associated type.
            public static func optionalAssociatedType(named name: String) -> Self {
                optional(wrapping: associatedType(named: name))
            }

            /// Describes an array whose element is the named associated type.
            public static func arrayOfAssociatedType(named name: String) -> Self {
                array(of: associatedType(named: name))
            }

            /// Describes a set whose element is the named associated type.
            ///
            /// The associated type's concrete binding must conform to
            /// `Hashable`, as required by `Set`.
            public static func setOfAssociatedType(named name: String) -> Self {
                set(of: associatedType(named: name))
            }

            /// Describes an optional wrapping another requirement value schema.
            ///
            /// Compose this factory with ``array(of:)``, ``set(of:)``, or
            /// ``dictionary(key:value:)`` to describe recursively nested
            /// standard-library containers.
            public static func optional(wrapping value: Self) -> Self {
                Self(
                    source: .optional(value.source),
                    ownership: nil
                )
            }

            /// Describes an array whose element uses another requirement value schema.
            public static func array(of element: Self) -> Self {
                Self(source: .array(element.source), ownership: nil)
            }

            /// Describes a set whose element uses another requirement value schema.
            ///
            /// The resolved element type must conform to `Hashable`.
            public static func set(of element: Self) -> Self {
                Self(source: .set(element.source), ownership: nil)
            }

            /// Describes a Dictionary whose key and value use requirement value schemas.
            ///
            /// The resolved key type must conform to `Hashable`.
            public static func dictionary(key: Self, value: Self) -> Self {
                Self(
                    source: .dictionary(
                        key: key.source,
                        value: value.source
                    ),
                    ownership: nil
                )
            }

            /// Describes a Dictionary with a concrete key and an associated value.
            public static func dictionary<Key: Hashable>(
                key: Key.Type,
                valueAssociatedTypeNamed valueName: String
            ) -> Self {
                Self(
                    source: .dictionary(
                        key: .concrete(key),
                        value: .associatedType(valueName)
                    ),
                    ownership: nil
                )
            }

            /// Describes a Dictionary with an associated key and a concrete value.
            ///
            /// The associated key's concrete binding must conform to `Hashable`.
            public static func dictionary<Value>(
                keyAssociatedTypeNamed keyName: String,
                value: Value.Type
            ) -> Self {
                Self(
                    source: .dictionary(
                        key: .associatedType(keyName),
                        value: .concrete(value)
                    ),
                    ownership: nil
                )
            }

            /// Describes a Dictionary whose key and value are associated types.
            ///
            /// The associated key's concrete binding must conform to `Hashable`.
            public static func dictionary(
                keyAssociatedTypeNamed keyName: String,
                valueAssociatedTypeNamed valueName: String
            ) -> Self {
                Self(
                    source: .dictionary(
                        key: .associatedType(keyName),
                        value: .associatedType(valueName)
                    ),
                    ownership: nil
                )
            }

            /// Returns a value that describes a consuming method argument.
            ///
            /// Apply this transform to a direct associated type or a supported
            /// container whose value depends on an associated type. Consuming
            /// concrete values, independent values, and requirement results
            /// are rejected when the requirement is validated.
            public func consuming() -> Self {
                Self(source: source, ownership: .owned)
            }

            /// Describes a consuming direct occurrence of the named associated type.
            ///
            /// Use this value for a `consuming` method parameter. Setter and
            /// initializer parameters are already owned by their requirement kind.
            public static func consumingAssociatedType(named name: String) -> Self {
                associatedType(named: name).consuming()
            }
        }

        let kind: StubRequirementKind
        let arguments: [Value]
        let result: Value
        let typedErrorType: Any.Type?
        let typedErrorAssociatedTypeName: String?
        let isThrowing: Bool
        let isAsync: Bool
        let typedWitnessAdapterFactory: TypedWitnessAdapterFactory?
        let inferredFromSignature: Bool

        private init(
            kind: StubRequirementKind,
            arguments: [Value],
            result: Value,
            typedErrorType: Any.Type? = nil,
            typedErrorAssociatedTypeName: String? = nil,
            isThrowing: Bool,
            isAsync: Bool,
            typedWitnessAdapterFactory: TypedWitnessAdapterFactory? = nil,
            inferredFromSignature: Bool = false
        ) {
            self.kind = kind
            self.arguments = arguments
            self.result = result
            self.typedErrorType = typedErrorType
            self.typedErrorAssociatedTypeName = typedErrorAssociatedTypeName
            self.isThrowing = isThrowing
            self.isAsync = isAsync
            self.typedWitnessAdapterFactory = typedWitnessAdapterFactory
            self.inferredFromSignature = inferredFromSignature
        }

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
            containsAssociatedTypes: Bool,
            selfIsClassConstrained: Bool
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
                    .associatedType(id: binding.id)
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
                selfIsClassConstrained: selfIsClassConstrained,
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

    /// Explicit requirements declared by one protocol in a composition.
    ///
    /// Create groups with `requirements(declaredBy:_:)` and pass them to the
    /// grouped Stub initializer. Groups may appear in any order;
    /// requirements inside a group remain in declaration order.
    public struct ProtocolRequirements: Sendable {
        let protocolType: Any.Type
        let requirements: [Requirement]

        /// Groups requirements by the protocol that directly declares them.
        ///
        /// Inherited requirements belong to the protocol where they were
        /// originally declared, and a shared base protocol is grouped once.
        public static func requirements(
            declaredBy protocolType: Any.Type,
            _ requirements: Requirement...
        ) -> Self {
            Self(protocolType: protocolType, requirements: requirements)
        }
    }
}
