/// An opaque typed-witness adapter factory supplied by the semantic layer.
/// Erases the concrete type so source-level requirement construction avoids
/// importing ABI metadata types; only the runtime recovers it via ``payload(as:)``.
package struct RuntimeTypedWitnessAdapterToken: @unchecked Sendable {
    private let erasedPayload: Any

    package init(payload: Any) {
        erasedPayload = payload
    }

    package func payload<Payload>(as type: Payload.Type) -> Payload? {
        erasedPayload as? Payload
    }
}

/// A source-level factory for a compiler-emitted typed witness adapter. The
/// semantic layer supplies the adapter's type, entry point, and invocation
/// object; Metadata converts it into the ABI adapter object.
package struct RuntimeTypedWitnessAdapterSource: @unchecked Sendable {
    package let functionType: Any.Type
    package let invocationType: Any.Type
    package let entryPoint: UInt
    package let makeInvocation:
        @Sendable (
            any RuntimeInvocationEndpoint,
            Int
        ) -> AnyObject

    package init(
        functionType: Any.Type,
        invocationType: Any.Type,
        entryPoint: UInt,
        makeInvocation:
            @escaping @Sendable (
                any RuntimeInvocationEndpoint,
                Int
            ) -> AnyObject
    ) {
        self.functionType = functionType
        self.invocationType = invocationType
        self.entryPoint = entryPoint
        self.makeInvocation = makeInvocation
    }
}

/// Source-level requirement data normalized for runtime metadata resolution.
/// Public factories build this dependency-free schema; the metadata runtime
/// resolves associated types, class constraints, and ABI transport when
/// turning it into a private method descriptor.
package struct RuntimeExplicitRequirementSchema: @unchecked Sendable {
    /// One source-level value in an explicit requirement.
    package struct Value: Sendable {
        package let source: Source
        package let ownership: RuntimeArgumentOwnership?

        package init(
            source: Source,
            ownership: RuntimeArgumentOwnership?
        ) {
            self.source = source
            self.ownership = ownership
        }
    }

    /// A recursive source-level type expression.
    package indirect enum Source: @unchecked Sendable {
        case concrete(Any.Type)
        case associatedType(String)
        case optional(Source)
        case array(Source)
        case set(Source)
        case dictionary(key: Source, value: Source)
        case result(success: Source, failure: Source)
        case selfType(isOptional: Bool)
        /// Typed by the requirement's own generic parameter.
        case methodGenericParameter(index: Int)
    }

    package let kind: RuntimeRequirementKind
    package let arguments: [Value]
    package let result: Value
    package let typedErrorType: Any.Type?
    package let typedErrorAssociatedTypeName: String?
    package let isThrowing: Bool
    package let isAsync: Bool
    package let typedWitnessAdapter: RuntimeTypedWitnessAdapterToken?
    package let inferredFromSignature: Bool
    package let erasedSelfType: Any.Type
    package let erasedOptionalSelfType: Any.Type

    package init(
        kind: RuntimeRequirementKind,
        arguments: [Value],
        result: Value,
        typedErrorType: Any.Type?,
        typedErrorAssociatedTypeName: String?,
        isThrowing: Bool,
        isAsync: Bool,
        typedWitnessAdapter: RuntimeTypedWitnessAdapterToken?,
        inferredFromSignature: Bool,
        erasedSelfType: Any.Type,
        erasedOptionalSelfType: Any.Type
    ) {
        self.kind = kind
        self.arguments = arguments
        self.result = result
        self.typedErrorType = typedErrorType
        self.typedErrorAssociatedTypeName = typedErrorAssociatedTypeName
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.typedWitnessAdapter = typedWitnessAdapter
        self.inferredFromSignature = inferredFromSignature
        self.erasedSelfType = erasedSelfType
        self.erasedOptionalSelfType = erasedOptionalSelfType
    }
}
