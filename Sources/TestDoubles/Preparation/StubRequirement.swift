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
                case result(success: Source, failure: Source)
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

        init(
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
