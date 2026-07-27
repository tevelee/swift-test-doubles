import CTestDoublesTrampoline
import EchoRuntimeReflection
import EchoRuntimeSupport
import Foundation
import TestDoublesRuntimeMetadata

/// Restores the concrete calling convention of function values that crossed
/// the recorder's generic `Any` boundary. Swift emits both directions of this
/// reabstraction pair in the client that performs the erased conversion, so no
/// protocol source annotation or generated forwarding body is required.
package enum FunctionReabstraction {
    package static func hasLinkedThunks(for type: Any.Type) -> Bool {
        ReabstractionThunkRegistry.shared.hasBothDirections(for: type)
    }

    package static func hasDirectToGenericBridge(_ function: FunctionTypeInfo) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(function) == nil,
            automaticClosureUnsupportedReason(function) == nil
        else {
            return false
        }
        return canDynamicallyBoxFunctionArgument(function)
            || ReabstractionThunkRegistry.shared.directToGeneric(
                for: function.type
            ) != nil
    }

    package static func hasGenericToDirectBridge(_ function: FunctionTypeInfo) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(function) == nil,
            automaticClosureUnsupportedReason(function) == nil
        else {
            return false
        }
        return canDynamicallyInitializeFunctionResult(function)
            || ReabstractionThunkRegistry.shared.genericToDirect(
                for: function.type
            ) != nil
    }

    package static func pointerAuthDiscriminators(
        for type: Any.Type
    ) -> (direct: UInt16, generic: UInt16)? {
        guard let function = FunctionTypeInfo(reflecting: type),
            let direct = directFunctionDiscriminator(for: function)
        else { return nil }
        return (
            direct,
            td_generic_function_discriminator(
                UInt16(function.parameters.count),
                function.resultType != Void.self
            )
        )
    }

    package static func automaticArgumentUnsupportedReason(for type: Any.Type) -> String? {
        guard let function = FunctionTypeInfo(reflecting: type) else { return nil }
        guard let convention = function.convention else {
            return "The closure has an unknown calling convention."
        }
        switch convention {
            case .c, .block:
                return nil
            case .thin:
                return "Thin function values cannot be constructed reliably by this Swift toolchain."
            case .swift:
                break
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(function) {
            return reason
        }
        if let reason = automaticClosureUnsupportedReason(function) {
            return reason
        }
        guard directFunctionDiscriminator(for: function) != nil else {
            return "The closure's pointer-authentication type spelling cannot be reconstructed safely."
        }
        guard let reason = dynamicFunctionBridgeUnsupportedReason(function) else {
            return nil
        }
        guard
            ReabstractionThunkRegistry.shared.directToGeneric(
                for: function.type
            ) == nil
        else {
            return nil
        }
        return "No matching compiler-emitted closure reabstraction thunk is linked. \(reason)"
    }

    package static func automaticResultUnsupportedReason(for type: Any.Type) -> String? {
        guard let function = FunctionTypeInfo(reflecting: type) else { return nil }
        guard let convention = function.convention else {
            return "The closure has an unknown calling convention."
        }
        switch convention {
            case .c, .block:
                return nil
            case .thin:
                return "Thin function values cannot be constructed reliably by this Swift toolchain."
            case .swift:
                break
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(function) {
            return reason
        }
        if let reason = automaticClosureUnsupportedReason(function) {
            return reason
        }
        guard directFunctionDiscriminator(for: function) != nil else {
            return "The closure's pointer-authentication type spelling cannot be reconstructed safely."
        }
        guard let reason = dynamicFunctionReturnBridgeUnsupportedReason(function)
        else {
            return nil
        }
        guard
            ReabstractionThunkRegistry.shared.genericToDirect(
                for: function.type
            ) == nil
        else {
            return nil
        }
        return "No matching compiler-emitted generic-to-direct closure reabstraction thunk is linked. \(reason)"
    }

    /// These effects cannot be matched to a compiler thunk with complete type
    /// identity. Global-actor identity is absent from the public demangler's
    /// lowered thunk spelling, while unknown extended bits have no semantics
    /// this runtime can validate.
    private static func automaticClosureUnsupportedReason(
        _ function: FunctionTypeInfo
    ) -> String? {
        guard function.effects.globalActorType == nil else {
            return "Global-actor functions require an executor-preserving bridge whose actor identity can be verified."
        }
        guard hasOnlyExactlyMatchableExtendedFlags(function) else {
            let rawFlags = function.effects.rawExtendedFlags ?? 0
            return "Unknown extended function flags \(String(format: "0x%08X", rawFlags)) cannot be matched to a compiler reabstraction thunk safely."
        }
        return nil
    }

    package static func boxDirectArgument(
        type: Any.Type,
        source: UnsafeMutableRawPointer
    ) -> Any {
        guard let function = FunctionTypeInfo(reflecting: type) else {
            preconditionFailure(
                "[TestDoubles] Expected function metadata for argument \(type)."
            )
        }
        guard let convention = function.convention else {
            preconditionFailure(
                "[TestDoubles] Function argument \(type) has an unknown calling convention."
            )
        }
        switch convention {
            case .c, .block:
                return boxValue(type: type, source: source)
            case .thin:
                preconditionFailure(
                    "[TestDoubles] Thin function arguments are not supported automatically."
                )
            case .swift:
                break
        }
        guard let code = source.load(as: UnsafeRawPointer?.self) else {
            preconditionFailure(
                "[TestDoubles] Function argument \(type) has no entry point."
            )
        }
        let context = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)
        if let plan = FunctionBridgeAnalysis(function).validated(
            for: .directToGeneric
        ),
            let discriminator = directFunctionDiscriminator(for: function)
        {
            return dynamicallyBoxFunctionArgument(
                function: code,
                context: context,
                plan: plan,
                discriminator: discriminator
            )
        }
        guard
            let thunk = ReabstractionThunkRegistry.shared.directToGeneric(
                for: function.type
            )
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted reabstraction thunk is linked for function argument \(type)."
            )
        }
        let state = ReabstractionContext(
            function: code,
            context: context,
            isIsolatedAny: function.effects.isIsolatedAny
        )
        state.validateStoredLayout()
        let discriminator = td_generic_function_discriminator(
            UInt16(function.parameters.count),
            function.resultType != Void.self
        )
        let signedThunk = td_sign_function_pointer(thunk, discriminator) ?? thunk
        func boxOpened<T>(_ type: T.Type) -> Any {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { storage.deallocate() }
            let raw = UnsafeMutableRawPointer(storage)
            raw.storeBytes(of: signedThunk, as: UnsafeRawPointer.self)
            (raw + MemoryLayout<UInt>.size).storeBytes(
                of: UnsafeRawPointer(RetainedRuntimeState.retain(state)),
                as: UnsafeRawPointer.self
            )
            return storage.move()
        }
        return _openExistential(type, do: boxOpened)
    }

    package static func initializeGenericSource(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        guard let code = source.load(as: UnsafeRawPointer?.self) else {
            ValueOperations.initializeCopy(
                of: type,
                from: source,
                to: destination
            )
            return
        }
        let context = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)

        guard let function = FunctionTypeInfo(reflecting: type),
            let discriminator = directFunctionDiscriminator(for: function)
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted generic-to-direct reabstraction thunk is linked for function result \(type)."
            )
        }
        if let plan = FunctionBridgeAnalysis(function).validated(
            for: .genericToDirect
        ) {
            initializeDynamicFunctionResult(
                source,
                plan: plan,
                discriminator: discriminator,
                at: destination
            )
            return
        }
        guard
            let thunk = ReabstractionThunkRegistry.shared.genericToDirect(
                for: function.type
            )
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted generic-to-direct reabstraction thunk is linked for function result \(type)."
            )
        }
        let state = ReabstractionContext(
            function: code,
            context: context,
            isIsolatedAny: function.effects.isIsolatedAny
        )
        state.validateStoredLayout()
        let signedThunk = td_sign_function_pointer(thunk, discriminator) ?? thunk
        destination.storeBytes(of: signedThunk, as: UnsafeRawPointer.self)
        (destination + MemoryLayout<UInt>.size).storeBytes(
            of: UnsafeRawPointer(RetainedRuntimeState.retain(state)),
            as: UnsafeRawPointer.self
        )
    }
}
