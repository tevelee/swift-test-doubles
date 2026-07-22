import Echo

private let unsupportedDynamicValueFlags = UInt32(0x0080_0000)

enum FunctionBridgeDirection: Sendable, Equatable {
    case directToGeneric
    case genericToDirect
}

/// Immutable ABI and effect facts shared by dynamic function validation in
/// both bridge directions.
struct FunctionBridgeAnalysis: @unchecked Sendable {
    let architecture: RuntimeArchitecture
    let metadata: FunctionMetadata
    let parameterTypes: [Any.Type]
    let directArgumentPlan: DynamicFunctionArgumentPlan?
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
    let genericUsesStackArgument: Bool

    init(
        _ metadata: FunctionMetadata,
        architecture: RuntimeArchitecture = .current
    ) {
        self.architecture = architecture
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
        genericUsesStackArgument =
            genericArgumentCount
            > architecture.generalPurposeArgumentRegisterCount
        directArgumentPlan = dynamicFunctionArgumentPlan(
            parameterTypes,
            initialGeneralPurposeOffset:
                asyncDirectResultUsesGeneralPurposeSlot ? 1 : 0,
            trailingGeneralPurposeWordCount:
                directTypedErrorUsesIndirectResultSlot ? 1 : 0,
            architecture: architecture
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
            genericArgumentCount
                > dynamicGenericArgumentLimit(architecture: architecture)
        {
            return "The dynamic return bridge exceeds its bounded generic argument register and stack budget."
        }
        if direction == .genericToDirect,
            architecture == .x86_64,
            isAsync,
            typedErrorType != nil,
            genericUsesStackArgument,
            directArgumentPlan?.usesStackArgument == false
        {
            return "The x86_64 async typed-error return bridge cannot mix a full direct register bank with generic stack transport."
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
        guard directArgumentPlan != nil else {
            return "The parameters exceed the architecture's bounded direct register and stack budget."
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

    func validated(
        for direction: FunctionBridgeDirection
    ) -> FunctionBridgePlan? {
        guard unsupportedReason(for: direction) == nil,
            let directArgumentPlan
        else {
            return nil
        }
        return FunctionBridgePlan(
            analysis: self,
            directArgumentPlan: directArgumentPlan,
            direction: direction
        )
    }
}

/// A bridge analysis whose support boundary has been checked for one runtime
/// direction. Execution consumes this type so it cannot observe a missing
/// direct argument transport plan after validation has succeeded.
struct FunctionBridgePlan: @unchecked Sendable {
    private let analysis: FunctionBridgeAnalysis

    let directArgumentPlan: DynamicFunctionArgumentPlan
    let direction: FunctionBridgeDirection

    fileprivate init(
        analysis: FunctionBridgeAnalysis,
        directArgumentPlan: DynamicFunctionArgumentPlan,
        direction: FunctionBridgeDirection
    ) {
        self.analysis = analysis
        self.directArgumentPlan = directArgumentPlan
        self.direction = direction
    }

    var metadata: FunctionMetadata { analysis.metadata }
    var parameterTypes: [Any.Type] { analysis.parameterTypes }
    var resultType: Any.Type { analysis.resultType }
    var resultLayout: ABIClass { analysis.resultLayout }
    var typedErrorType: Any.Type? { analysis.typedErrorType }
    var typedErrorLayout: ABIClass? { analysis.typedErrorLayout }
    var isAsync: Bool { analysis.isAsync }
    var isThrowing: Bool { analysis.isThrowing }
    var directTypedErrorUsesIndirectResultSlot: Bool {
        analysis.directTypedErrorUsesIndirectResultSlot
    }
    var genericTypedErrorUsesIndirectResultSlot: Bool {
        analysis.genericTypedErrorUsesIndirectResultSlot
    }
    var asyncDirectResultUsesGeneralPurposeSlot: Bool {
        analysis.asyncDirectResultUsesGeneralPurposeSlot
    }
    var genericUsesStackArgument: Bool {
        analysis.genericUsesStackArgument
    }

    var directArgumentLayouts: [ABIClass] { directArgumentPlan.layouts }
}
