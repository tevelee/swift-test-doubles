import Echo

private let unsupportedDynamicValueFlags = UInt32(0x0080_0000)

enum FunctionBridgeDirection: Sendable {
    case directToGeneric
    case genericToDirect
}

/// Immutable ABI and effect facts shared by dynamic function validation and
/// execution. A bridge is analyzed once, then both directions consume the
/// same layouts, error transport, and register offsets.
struct FunctionBridgePlan: @unchecked Sendable {
    let metadata: FunctionMetadata
    let parameterTypes: [Any.Type]
    let directArgumentLayouts: [ABIClass]?
    let resultType: Any.Type
    let resultLayout: ABIClass
    let typedErrorType: Any.Type?
    let typedErrorLayout: ABIClass?
    let isAsync: Bool
    let isThrowing: Bool
    let directTypedErrorUsesIndirectResultSlot: Bool
    let genericTypedErrorUsesIndirectResultSlot: Bool
    let asyncDirectResultUsesGeneralPurposeSlot: Bool
    let genericArgumentCount: Int

    init(_ metadata: FunctionMetadata) {
        self.metadata = metadata
        parameterTypes = safeFunctionParameterTypes(metadata)
        resultType = metadata.resultType
        resultLayout = abiClass(for: metadata.resultType, isReturn: true)
        typedErrorType = metadata.typedThrownErrorType
        typedErrorLayout = metadata.typedThrownErrorType.map {
            abiClass(for: $0, isReturn: true)
        }
        isAsync = isDynamicFunctionAsync(metadata)
        isThrowing = metadata.flags.throws
        directTypedErrorUsesIndirectResultSlot =
            dynamicDirectTypedErrorUsesIndirectResultSlot(metadata)
        genericTypedErrorUsesIndirectResultSlot =
            dynamicGenericTypedErrorUsesIndirectResultSlot(metadata)
        asyncDirectResultUsesGeneralPurposeSlot =
            isAsync && abiClassIsIndirect(resultLayout)
        genericArgumentCount =
            metadata.flags.numParams
            + (genericTypedErrorUsesIndirectResultSlot ? 1 : 0)
            + (isAsync && metadata.resultType != Void.self ? 1 : 0)
        directArgumentLayouts = dynamicArgumentLayouts(
            parameterTypes,
            additionalGeneralPurpose: (directTypedErrorUsesIndirectResultSlot ? 1 : 0)
                + (asyncDirectResultUsesGeneralPurposeSlot ? 1 : 0)
        )
    }

    func unsupportedReason(for direction: FunctionBridgeDirection) -> String? {
        guard metadata.flags.convention == .swift else {
            return "Only native Swift functions need this bridge."
        }
        if direction == .directToGeneric, metadata.flags.numParams > 6 {
            return "The dynamic bridge currently supports at most six parameters."
        }
        if direction == .genericToDirect,
            genericArgumentCount > dynamicGenericArgumentLimit()
        {
            return "The dynamic return bridge exceeds the architecture's generic argument register budget."
        }
        guard metadata.flags.bits & 0x0800_0000 == 0 else {
            return "Differentiable functions require derivative metadata."
        }
        guard metadata.globalActorType == nil else {
            return "Global-actor functions require an executor-preserving bridge."
        }
        guard hasOnlyDynamicallySupportedExtendedFlags(metadata) else {
            return "Extended isolation, sending, or invertible-protocol flags require compiler reabstraction."
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(metadata) {
            return reason
        }
        guard reflect(resultType).vwt.flags.bits & unsupportedDynamicValueFlags == 0 else {
            return "The result is noncopyable."
        }
        if let typedErrorType {
            guard typedErrorType is any Error.Type else {
                return "The typed-throws result does not conform to Error."
            }
            guard
                reflect(typedErrorType).vwt.flags.bits & unsupportedDynamicValueFlags == 0
            else {
                return "The typed error is noncopyable."
            }
            if direction == .genericToDirect,
                FunctionReabstraction.canBoxDirectResult(of: typedErrorType) == false
                    || FunctionReabstraction.canInitializeDirectValue(of: typedErrorType) == false
            {
                return "The typed error cannot cross generic storage recursively."
            }
        }
        guard
            parameterTypes.allSatisfy({
                reflect($0).vwt.flags.bits & unsupportedDynamicValueFlags == 0
            })
        else {
            return "A parameter is noncopyable."
        }
        let parametersCanCrossBoundary: Bool
        switch direction {
            case .directToGeneric:
                parametersCanCrossBoundary = parameterTypes.allSatisfy {
                    FunctionReabstraction.canInitializeDirectValue(of: $0)
                }
            case .genericToDirect:
                parametersCanCrossBoundary = parameterTypes.allSatisfy {
                    FunctionReabstraction.canBoxDirectResult(of: $0)
                }
        }
        guard parametersCanCrossBoundary else {
            switch direction {
                case .directToGeneric:
                    return "A nested function parameter lacks generic-to-direct reabstraction."
                case .genericToDirect:
                    return "A nested function parameter cannot cross into generic storage."
            }
        }
        if metadata.flags.hasParamFlags,
            metadata.paramFlags.contains(where: { $0.bits != 0 })
        {
            return "Ownership, variadic, autoclosure, derivative, isolated, or sending parameter flags require compiler reabstraction."
        }
        guard directArgumentLayouts != nil else {
            return "The parameters exceed the architecture's direct register budget."
        }
        switch direction {
            case .directToGeneric:
                guard FunctionReabstraction.canBoxDirectResult(of: resultType) else {
                    return "A function-valued result cannot be boxed recursively."
                }
            case .genericToDirect:
                guard FunctionReabstraction.canInitializeDirectValue(of: resultType) else {
                    return "A function-valued result cannot be initialized recursively."
                }
        }
        return nil
    }
}
