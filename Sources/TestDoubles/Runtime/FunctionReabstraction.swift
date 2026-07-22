import CTestDoublesTrampoline
import Echo
import Foundation

/// Restores the concrete calling convention of function values that crossed
/// the recorder's generic `Any` boundary. Swift emits both directions of this
/// reabstraction pair in the client that performs the erased conversion, so no
/// protocol source annotation or generated forwarding body is required.
enum FunctionReabstraction {
    static func hasLinkedThunks(for type: Any.Type) -> Bool {
        guard let metadata = reflect(type) as? FunctionMetadata else {
            return false
        }
        return ReabstractionThunkRegistry.shared.hasBothDirections(for: metadata)
    }

    static func hasDirectToGenericBridge(_ metadata: FunctionMetadata) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(metadata) == nil else {
            return false
        }
        return canDynamicallyBoxFunctionArgument(metadata)
            || ReabstractionThunkRegistry.shared.directToGeneric(for: metadata) != nil
    }

    static func hasGenericToDirectBridge(_ metadata: FunctionMetadata) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(metadata) == nil else {
            return false
        }
        return canDynamicallyInitializeFunctionResult(metadata)
            || ReabstractionThunkRegistry.shared.genericToDirect(for: metadata) != nil
    }

    static func pointerAuthDiscriminators(
        for type: Any.Type
    ) -> (direct: UInt16, generic: UInt16)? {
        guard let function = reflect(type) as? FunctionMetadata,
            let direct = directFunctionDiscriminator(for: function)
        else { return nil }
        return (
            direct,
            td_generic_function_discriminator(
                UInt16(functionLoweredParameterCount(function)),
                function.resultType != Void.self
            )
        )
    }

    static func automaticArgumentUnsupportedReason(for type: Any.Type) -> String? {
        guard let metadata = reflect(type) as? FunctionMetadata else { return nil }
        switch metadata.flags.convention {
            case .c, .block:
                return nil
            case .thin:
                return "Thin function values cannot be constructed reliably by this Swift toolchain."
            case .swift:
                break
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(metadata) {
            return reason
        }
        guard directFunctionDiscriminator(for: metadata) != nil else {
            return "The closure's pointer-authentication type spelling cannot be reconstructed safely."
        }
        guard let reason = dynamicFunctionBridgeUnsupportedReason(metadata) else {
            return nil
        }
        guard ReabstractionThunkRegistry.shared.directToGeneric(for: metadata) == nil
        else {
            return nil
        }
        return "No matching compiler-emitted closure reabstraction thunk is linked. \(reason)"
    }

    static func automaticResultUnsupportedReason(for type: Any.Type) -> String? {
        guard let metadata = reflect(type) as? FunctionMetadata else { return nil }
        switch metadata.flags.convention {
            case .c, .block:
                return nil
            case .thin:
                return "Thin function values cannot be constructed reliably by this Swift toolchain."
            case .swift:
                break
        }
        if let reason = typedThrowingFunctionRuntimeUnsupportedReason(metadata) {
            return reason
        }
        guard directFunctionDiscriminator(for: metadata) != nil else {
            return "The closure's pointer-authentication type spelling cannot be reconstructed safely."
        }
        guard let reason = dynamicFunctionReturnBridgeUnsupportedReason(metadata)
        else {
            return nil
        }
        guard ReabstractionThunkRegistry.shared.genericToDirect(for: metadata) == nil
        else {
            return nil
        }
        return "No matching compiler-emitted generic-to-direct closure reabstraction thunk is linked. \(reason)"
    }

    static func boxDirectArgument(
        type: Any.Type,
        source: UnsafeMutableRawPointer
    ) -> Any {
        guard let function = reflect(type) as? FunctionMetadata else {
            preconditionFailure(
                "[TestDoubles] Expected function metadata for argument \(type)."
            )
        }
        switch function.flags.convention {
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
                for: function
            )
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted reabstraction thunk is linked for function argument \(type)."
            )
        }
        let state = ReabstractionContext(
            function: code,
            context: context,
            isIsolatedAny: function.isIsolatedAny
        )
        state.validateStoredLayout()
        let discriminator = td_generic_function_discriminator(
            UInt16(functionLoweredParameterCount(function)),
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

    static func initializeGenericSource(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        guard let code = source.load(as: UnsafeRawPointer?.self) else {
            reflect(type).vwt.initializeWithCopy(destination, source)
            return
        }
        let context = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)

        guard let function = reflect(type) as? FunctionMetadata,
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
                for: function
            )
        else {
            preconditionFailure(
                "[TestDoubles] No compiler-emitted generic-to-direct reabstraction thunk is linked for function result \(type)."
            )
        }
        let state = ReabstractionContext(
            function: code,
            context: context,
            isIsolatedAny: function.isIsolatedAny
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
