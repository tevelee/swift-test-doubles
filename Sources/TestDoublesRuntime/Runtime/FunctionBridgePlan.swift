import EchoRuntimeReflection
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport

package enum FunctionBridgeDirection: Sendable, Equatable {
    case directToGeneric
    case genericToDirect
}

/// Immutable ABI and effect facts shared by dynamic function validation in
/// both bridge directions.
package struct FunctionBridgeAnalysis: @unchecked Sendable {
    let architecture: RuntimeArchitecture
    let function: FunctionTypeInfo
    let parameterTypes: [Any.Type]
    let directArgumentPlan: DynamicFunctionArgumentPlan?
    let resultType: Any.Type
    let resultLayout: ABIClass
    let typedErrorType: Any.Type?
    let typedErrorLayout: ABIClass?
    let isAsync: Bool
    let isThrowing: Bool
    let isSendable: Bool
    let directTypedErrorUsesIndirectResultSlot: Bool
    let genericTypedErrorUsesIndirectResultSlot: Bool
    let asyncDirectResultUsesGeneralPurposeSlot: Bool
    let genericArgumentCount: Int
    let genericUsesStackArgument: Bool

    package init(
        _ function: FunctionTypeInfo,
        architecture: RuntimeArchitecture = .current
    ) {
        self.architecture = architecture
        self.function = function
        parameterTypes = function.parameters.map(\.type)
        resultType = function.resultType
        resultLayout = abiClass(for: function.resultType, isReturn: true)
        let typedErrorType = function.effects.typedErrorType
        self.typedErrorType = typedErrorType
        typedErrorLayout = typedErrorType.map {
            abiClass(for: $0, isReturn: true)
        }
        isAsync = function.effects.isAsync
        isThrowing = function.effects.isThrowing
        isSendable = function.effects.isSendable
        directTypedErrorUsesIndirectResultSlot =
            dynamicDirectTypedErrorUsesIndirectResultSlot(function)
        genericTypedErrorUsesIndirectResultSlot =
            dynamicGenericTypedErrorUsesIndirectResultSlot(function)
        asyncDirectResultUsesGeneralPurposeSlot =
            isAsync && abiClassIsIndirect(resultLayout)
        genericArgumentCount =
            function.parameters.count
            + (genericTypedErrorUsesIndirectResultSlot ? 1 : 0)
            + (isAsync && function.resultType != Void.self ? 1 : 0)
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

    package func unsupportedReason(for direction: FunctionBridgeDirection) -> String? {
        guard function.convention == .swift else {
            return "Only native Swift functions need this bridge."
        }
        if direction == .directToGeneric, function.parameters.count > 6 {
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
        guard function.effects.isDifferentiable == false else {
            return "Differentiable functions require derivative metadata."
        }
        guard function.effects.globalActorType == nil else {
            return "Global-actor functions require an executor-preserving bridge."
        }
        guard hasOnlyDynamicallySupportedExtendedFlags(function) else {
            return "Extended isolation, sending, or invertible-protocol flags require compiler reabstraction."
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(function) {
            return reason
        }
        if let reason = noncopyableDiagnosis(for: resultType, role: "The result") {
            return reason
        }
        if let typedErrorType {
            guard typedErrorType is any Error.Type else {
                return "The typed-throws result does not conform to Error."
            }
            if let reason = noncopyableDiagnosis(for: typedErrorType, role: "The typed error") {
                return reason
            }
            if direction == .genericToDirect,
                FunctionReabstraction.canBoxDirectResult(of: typedErrorType) == false
                    || FunctionReabstraction.canInitializeDirectValue(of: typedErrorType) == false
            {
                return "The typed error cannot cross generic storage recursively."
            }
        }
        for parameterType in parameterTypes {
            if let reason = noncopyableDiagnosis(for: parameterType, role: "A parameter") {
                return reason
            }
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
        if function.parameters.contains(where: { $0.rawFlags != 0 }) {
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

    /// Distinguishes an ordinary noncopyable value from a lifetime-dependent one
    /// (`isAddressableForDependencies`, e.g. `~Escapable`/`Span`-shaped values):
    /// the latter can never be held past the call that produced it, which an
    /// ordinary noncopyable-but-movable value at least admits in principle. Both
    /// still fail closed today -- this only sharpens which case a caller hit.
    private func noncopyableDiagnosis(for type: Any.Type, role: String) -> String? {
        let layout = ValueLayoutInfo(reflecting: type)
        guard layout.isCopyable == false else { return nil }
        if layout.isAddressableForDependencies {
            return "\(role) is lifetime-dependent (addressable for dependencies) and noncopyable. Runtime recording cannot box a value into `Any` or retain it past the call for a type shaped like this."
        }
        return "\(role) is noncopyable."
    }

    package func validated(
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
package struct FunctionBridgePlan: @unchecked Sendable {
    private let analysis: FunctionBridgeAnalysis

    package let directArgumentPlan: DynamicFunctionArgumentPlan
    package let direction: FunctionBridgeDirection

    fileprivate init(
        analysis: FunctionBridgeAnalysis,
        directArgumentPlan: DynamicFunctionArgumentPlan,
        direction: FunctionBridgeDirection
    ) {
        self.analysis = analysis
        self.directArgumentPlan = directArgumentPlan
        self.direction = direction
    }

    package var function: FunctionTypeInfo { analysis.function }
    package var parameterTypes: [Any.Type] { analysis.parameterTypes }
    package var resultType: Any.Type { analysis.resultType }
    package var resultLayout: ABIClass { analysis.resultLayout }
    package var typedErrorType: Any.Type? { analysis.typedErrorType }
    package var typedErrorLayout: ABIClass? { analysis.typedErrorLayout }
    package var isAsync: Bool { analysis.isAsync }
    package var isThrowing: Bool { analysis.isThrowing }
    package var isSendable: Bool { analysis.isSendable }
    package var directTypedErrorUsesIndirectResultSlot: Bool {
        analysis.directTypedErrorUsesIndirectResultSlot
    }
    package var genericTypedErrorUsesIndirectResultSlot: Bool {
        analysis.genericTypedErrorUsesIndirectResultSlot
    }
    package var asyncDirectResultUsesGeneralPurposeSlot: Bool {
        analysis.asyncDirectResultUsesGeneralPurposeSlot
    }
    package var genericUsesStackArgument: Bool {
        analysis.genericUsesStackArgument
    }

    package var directArgumentLayouts: [ABIClass] { directArgumentPlan.layouts }
}
