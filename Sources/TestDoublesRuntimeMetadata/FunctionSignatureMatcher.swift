import EchoRuntimeReflection

enum FunctionSignatureMatcher {
    static func direct(
        _ parsed: LoweredFunctionSyntax,
        matches function: FunctionTypeInfo
    ) -> Bool {
        let parsedGlobalActor = parsed.globalActor.flatMap(resolveRuntimeType)
        guard parsed.isSendable == function.effects.isSendable,
            parsed.isEscaping == function.effects.isEscaping,
            parsed.isIsolated == function.effects.isIsolatedAny,
            parsed.globalActor == nil || parsedGlobalActor != nil,
            parsed.globalActor == nil
                || sameRuntimeType(
                    parsedGlobalActor,
                    function.effects.globalActorType
                ),
            parsed.isAsync == function.effects.isAsync,
            parsed.isThrowing == function.effects.isThrowing,
            parsed.hasSendingResult == runtimeFunctionHasSendingResult(function),
            thrownError(parsed.thrownError, matches: function),
            type(parsed.result, matches: function.resultType)
        else {
            return false
        }
        return parameters(parsed.parameters, match: function)
    }

    /// Generic reabstraction signatures can contain demangler-only
    /// `@substituted` spellings that have no runtime type parser. Match their
    /// complete semantic envelope after trying the stronger concrete parser,
    /// so a same-shaped sync-to-async or throwing conversion thunk cannot be
    /// selected by accident.
    static func generic(
        _ parsed: LoweredFunctionSyntax,
        matches function: FunctionTypeInfo
    ) -> Bool {
        if direct(parsed, matches: function) { return true }
        let parsedGlobalActor = parsed.globalActor.flatMap(resolveRuntimeType)
        return parsed.isSendable
            == function.effects.isSendable
            && parsed.isEscaping
                == function.effects.isEscaping
            && parsed.isIsolated
                == function.effects.isIsolatedAny
            && (parsed.globalActor == nil || parsedGlobalActor != nil)
            && (parsed.globalActor == nil
                || sameRuntimeType(
                    parsedGlobalActor,
                    function.effects.globalActorType
                ))
            && parsed.isAsync == function.effects.isAsync
            && parsed.isThrowing == function.effects.isThrowing
            && parsed.hasSendingResult == runtimeFunctionHasSendingResult(function)
            && parsed.parameters.count
                == function.parameters.count
                + (function.effects.isNonisolatedNonsending ? 1 : 0)
            && parameterEffects(parsed.parameters, match: function)
    }

    private static func parameters(
        _ parsed: [LoweredFunctionParameterSyntax],
        match function: FunctionTypeInfo
    ) -> Bool {
        var semanticParameters = parsed[...]
        if function.effects.isNonisolatedNonsending {
            guard case .implicitActor? = semanticParameters.first?.type else {
                return false
            }
            semanticParameters = semanticParameters.dropFirst()
        }
        guard semanticParameters.count == function.parameters.count else {
            return false
        }
        return zip(semanticParameters, function.parameters).allSatisfy { pair in
            type(
                pair.0.type,
                matches: loweredFunctionParameterType(
                    pair.1
                )
            )
                && pair.0.ownership == UInt32(pair.1.rawOwnership)
                && pair.0.isIsolated == pair.1.isIsolated
                && pair.0.isSending == pair.1.isSending
        }
    }

    private static func parameterEffects(
        _ parsed: [LoweredFunctionParameterSyntax],
        match function: FunctionTypeInfo
    ) -> Bool {
        var semanticParameters = parsed[...]
        if function.effects.isNonisolatedNonsending {
            guard case .implicitActor? = semanticParameters.first?.type else {
                return false
            }
            semanticParameters = semanticParameters.dropFirst()
        }
        guard semanticParameters.count == function.parameters.count else {
            return false
        }
        return zip(semanticParameters, function.parameters).allSatisfy {
            $0.isIsolated == $1.isIsolated
                && $0.isSending == $1.isSending
        }
    }

    private static func loweredFunctionParameterType(
        _ parameter: FunctionTypeInfo.Parameter
    ) -> Any.Type {
        guard parameter.isVariadic else { return parameter.type }
        func arrayType<Element>(of type: Element.Type) -> Any.Type {
            [Element].self
        }
        return _openExistential(parameter.type, do: arrayType)
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
        matches function: FunctionTypeInfo
    ) -> Bool {
        if function.effects.isTypedThrows {
            guard let typed = function.effects.typedErrorType else { return false }
            guard let parsed else { return false }
            return type(parsed, matches: typed)
        }
        guard function.effects.isThrowing else { return parsed == nil }
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
                guard let function = FunctionTypeInfo(reflecting: runtimeType) else {
                    return false
                }
                return direct(signature, matches: function)
            case .implicitActor, .substituted:
                return false
        }
    }
}

/// Swift 6.3 does not consistently surface the sending-result bit through
/// function metadata, although the canonical runtime type spelling retains
/// it. Consult both representations so dynamic bridging cannot erase transfer
/// semantics and exact-thunk matching can require the result marker.
package func runtimeFunctionHasSendingResult(
    _ function: FunctionTypeInfo
) -> Bool {
    if let rawFlags = function.effects.rawExtendedFlags,
        rawFlags & 0x10 != 0
    {
        return true
    }
    guard
        case .function(let syntax)? = DemangledTypeSyntax(
            String(reflecting: function.type)
        )
    else {
        return false
    }
    return syntax.hasSendingResult
}
