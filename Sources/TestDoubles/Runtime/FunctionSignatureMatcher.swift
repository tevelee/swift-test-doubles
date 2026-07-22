import Echo

enum FunctionSignatureMatcher {
    static func direct(
        _ parsed: LoweredFunctionSyntax,
        matches metadata: FunctionMetadata
    ) -> Bool {
        let parsedGlobalActor = parsed.globalActor.flatMap(resolveRuntimeType)
        guard parsed.isSendable == (metadata.flags.bits & 0x4000_0000 != 0),
            parsed.isEscaping == (metadata.flags.bits & 0x0400_0000 != 0),
            parsed.isIsolated == metadata.isIsolatedAny,
            parsed.globalActor == nil || parsedGlobalActor != nil,
            parsed.globalActor == nil
                || sameRuntimeType(parsedGlobalActor, metadata.globalActorType),
            parsed.isAsync == functionIsAsync(metadata),
            parsed.isThrowing == metadata.flags.throws,
            thrownError(parsed.thrownError, matches: metadata),
            type(parsed.result, matches: metadata.resultType)
        else {
            return false
        }
        return parameters(parsed.parameters, match: metadata)
    }

    /// Generic reabstraction signatures can contain demangler-only
    /// `@substituted` spellings that have no runtime type parser. Match their
    /// complete semantic envelope after trying the stronger concrete parser,
    /// so a same-shaped sync-to-async or throwing conversion thunk cannot be
    /// selected by accident.
    static func generic(
        _ parsed: LoweredFunctionSyntax,
        matches metadata: FunctionMetadata
    ) -> Bool {
        if direct(parsed, matches: metadata) { return true }
        let parsedGlobalActor = parsed.globalActor.flatMap(resolveRuntimeType)
        return parsed.isSendable
            == (metadata.flags.bits & 0x4000_0000 != 0)
            && parsed.isEscaping
                == (metadata.flags.bits & 0x0400_0000 != 0)
            && parsed.isIsolated == metadata.isIsolatedAny
            && (parsed.globalActor == nil || parsedGlobalActor != nil)
            && (parsed.globalActor == nil
                || sameRuntimeType(parsedGlobalActor, metadata.globalActorType))
            && parsed.isAsync == functionIsAsync(metadata)
            && parsed.isThrowing == metadata.flags.throws
            && parsed.parameters.count == functionLoweredParameterCount(metadata)
    }

    private static func parameters(
        _ parsed: [LoweredFunctionParameterSyntax],
        match metadata: FunctionMetadata
    ) -> Bool {
        var semanticParameters = parsed[...]
        if metadata.isNonisolatedNonsending {
            guard case .implicitActor? = semanticParameters.first?.type else {
                return false
            }
            semanticParameters = semanticParameters.dropFirst()
        }
        let runtimeParameterTypes = safeFunctionParameterTypes(metadata)
        guard semanticParameters.count == runtimeParameterTypes.count else {
            return false
        }
        return zip(semanticParameters, runtimeParameterTypes).enumerated().allSatisfy {
            index, pair in
            type(
                pair.0.type,
                matches: loweredFunctionParameterType(
                    metadata,
                    type: runtimeParameterTypes[index],
                    at: index
                )
            )
                && pair.0.ownership == functionParameterOwnership(metadata, at: index)
                && pair.0.isIsolated == functionParameterIsIsolated(metadata, at: index)
        }
    }

    private static func sameRuntimeType(
        _ lhs: Any.Type?,
        _ rhs: Any.Type?
    ) -> Bool {
        switch (lhs, rhs) {
            case (nil, nil): return true
            case (.some(let lhs), .some(let rhs)):
                return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
            default: return false
        }
    }

    private static func thrownError(
        _ parsed: LoweredTypeSyntax?,
        matches metadata: FunctionMetadata
    ) -> Bool {
        if let typed = metadata.typedThrownErrorType {
            guard let parsed else { return false }
            return type(parsed, matches: typed)
        }
        guard metadata.flags.throws else { return parsed == nil }
        guard case .source(let syntax)? = parsed,
            let type = resolveRuntimeType(syntax)
        else {
            return false
        }
        return ObjectIdentifier(type) == ObjectIdentifier((any Error).self)
    }

    private static func type(
        _ parsed: LoweredTypeSyntax,
        matches runtimeType: Any.Type
    ) -> Bool {
        switch parsed {
            case .source(let syntax):
                guard let type = resolveRuntimeType(syntax) else { return false }
                return ObjectIdentifier(type) == ObjectIdentifier(runtimeType)
            case .function(let signature):
                guard let metadata = reflect(runtimeType) as? FunctionMetadata else {
                    return false
                }
                return direct(signature, matches: metadata)
            case .implicitActor, .substituted:
                return false
        }
    }
}
