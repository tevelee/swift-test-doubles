import CTestDoublesTrampoline
import EchoRuntimeReflection
import EchoRuntimeSupport
import Foundation
import InternalRuntimeContract

/// Restores the concrete calling convention of function values that crossed
/// the recorder's generic `Any` boundary. Swift emits both directions of this
/// reabstraction pair in the client that performs the erased conversion, so no
/// protocol source annotation or generated forwarding body is required.
package enum FunctionReabstraction {
    package static func prepare(
        type: Any.Type,
        direction: FunctionBridgeDirection,
        resultTransportEvidenceCatalog: CompilerResultTransportEvidenceCatalog = .empty
    ) -> PreparedFunctionReabstraction? {
        guard let function = FunctionTypeInfo(reflecting: type),
            let convention = function.convention
        else {
            return nil
        }
        switch convention {
            case .c, .block:
                guard direction == .directToGeneric else { return nil }
                return PreparedFunctionReabstraction(
                    type: type,
                    function: function,
                    execution: .copy
                )
            case .thin:
                return PreparedFunctionReabstraction(
                    type: type,
                    function: function,
                    execution: .unsupported(
                        direction == .directToGeneric
                            ? "[TestDoubles] Thin function arguments are not supported automatically."
                            : "[TestDoubles] Thin function results are not supported automatically."
                    )
                )
            case .swift:
                break
        }

        let analysis = FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: resultTransportEvidenceCatalog
        )
        if let bridge = analysis.validated(for: direction),
            let discriminator = directFunctionDiscriminator(for: function)
        {
            return PreparedFunctionReabstraction(
                type: type,
                function: function,
                execution: .dynamic(
                    bridge,
                    discriminator: discriminator
                )
            )
        }

        let thunk: UnsafeRawPointer?
        let discriminator: UInt16?
        switch direction {
            case .directToGeneric:
                thunk = ReabstractionThunkRegistry.shared.directToGeneric(
                    for: function.type
                )
                discriminator = td_generic_function_discriminator(
                    UInt16(function.parameters.count),
                    function.resultType != Void.self
                )
            case .genericToDirect:
                thunk = ReabstractionThunkRegistry.shared.genericToDirect(
                    for: function.type
                )
                discriminator = directFunctionDiscriminator(for: function)
        }

        let execution: PreparedFunctionReabstraction.Execution
        if let thunk, let discriminator {
            execution = .thunk(thunk, discriminator: discriminator)
        } else {
            execution = .unsupported(
                direction == .directToGeneric
                    ? "[TestDoubles] No compiler-emitted reabstraction thunk is linked for function argument \(type)."
                    : "[TestDoubles] No compiler-emitted generic-to-direct reabstraction thunk is linked for function result \(type)."
            )
        }
        return PreparedFunctionReabstraction(
            type: type,
            function: function,
            execution: execution
        )
    }

    package static func hasLinkedThunks(for type: Any.Type) -> Bool {
        ReabstractionThunkRegistry.shared.hasBothDirections(for: type)
    }

    package static func hasDirectToGenericBridge(
        _ function: FunctionTypeInfo,
        resultTransportEvidenceCatalog: CompilerResultTransportEvidenceCatalog = .empty
    ) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(function) == nil,
            automaticClosureUnsupportedReason(function) == nil
        else {
            return false
        }
        return FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: resultTransportEvidenceCatalog
        ).validated(for: .directToGeneric) != nil
            || ReabstractionThunkRegistry.shared.directToGeneric(
                for: function.type
            ) != nil
    }

    package static func hasGenericToDirectBridge(
        _ function: FunctionTypeInfo,
        resultTransportEvidenceCatalog: CompilerResultTransportEvidenceCatalog = .empty
    ) -> Bool {
        guard typedThrowingFunctionRuntimeUnsupportedReason(function) == nil,
            automaticClosureUnsupportedReason(function) == nil
        else {
            return false
        }
        return FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: resultTransportEvidenceCatalog
        ).validated(for: .genericToDirect) != nil
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

    package static func automaticArgumentUnsupportedReason(
        for type: Any.Type,
        resultTransportEvidenceCatalog: CompilerResultTransportEvidenceCatalog = .empty
    ) -> String? {
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
        guard
            let reason = FunctionBridgeAnalysis(
                function,
                resultTransportEvidenceCatalog: resultTransportEvidenceCatalog
            ).unsupportedReason(for: .directToGeneric)
        else {
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

    package static func automaticResultUnsupportedReason(
        for type: Any.Type,
        resultTransportEvidenceCatalog: CompilerResultTransportEvidenceCatalog = .empty
    ) -> String? {
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
        guard
            let reason = FunctionBridgeAnalysis(
                function,
                resultTransportEvidenceCatalog: resultTransportEvidenceCatalog
            ).unsupportedReason(for: .genericToDirect)
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
        guard
            let prepared = prepare(
                type: type,
                direction: .directToGeneric
            )
        else {
            preconditionFailure(
                "[TestDoubles] Expected function metadata for argument \(type)."
            )
        }
        return boxDirectArgument(prepared, source: source)
    }

    package static func boxDirectArgument(
        _ prepared: borrowing PreparedFunctionReabstraction,
        source: UnsafeMutableRawPointer
    ) -> Any {
        let type = prepared.type
        if case .copy = prepared.execution {
            return boxValue(type: type, source: source)
        }
        guard let code = source.load(as: UnsafeRawPointer?.self) else {
            preconditionFailure(
                "[TestDoubles] Function argument \(type) has no entry point."
            )
        }
        let context = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)

        switch prepared.execution {
            case .copy:
                preconditionFailure(
                    "[TestDoubles] Copy-only closure transport was handled before native function decoding."
                )
            case .dynamic(let plan, let discriminator):
                return dynamicallyBoxFunctionArgument(
                    function: code,
                    context: context,
                    plan: plan,
                    discriminator: discriminator
                )
            case .thunk(let thunk, let discriminator):
                let state = ReabstractionContext(
                    function: code,
                    context: context,
                    isIsolatedAny: prepared.function.effects.isIsolatedAny
                )
                state.validateStoredLayout()
                let signedThunk =
                    td_sign_function_pointer(thunk, discriminator) ?? thunk
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
            case .unsupported(let message):
                preconditionFailure(message)
        }
    }

    package static func initializeGenericSource(
        _ source: UnsafeMutableRawPointer,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        guard
            let prepared = prepare(
                type: type,
                direction: .genericToDirect
            )
        else {
            ValueOperations.initializeCopy(
                of: type,
                from: source,
                to: destination
            )
            return
        }
        initializeGenericSource(
            source,
            prepared: prepared,
            at: destination
        )
    }

    package static func initializeGenericSource(
        _ source: UnsafeMutableRawPointer,
        prepared: borrowing PreparedFunctionReabstraction,
        at destination: UnsafeMutableRawPointer
    ) {
        let type = prepared.type
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

        switch prepared.execution {
            case .copy:
                ValueOperations.initializeCopy(
                    of: type,
                    from: source,
                    to: destination
                )
            case .dynamic(let plan, let discriminator):
                initializeDynamicFunctionResult(
                    source,
                    plan: plan,
                    discriminator: discriminator,
                    at: destination
                )
            case .thunk(let thunk, let discriminator):
                let state = ReabstractionContext(
                    function: code,
                    context: context,
                    isIsolatedAny: prepared.function.effects.isIsolatedAny
                )
                state.validateStoredLayout()
                let signedThunk =
                    td_sign_function_pointer(thunk, discriminator) ?? thunk
                destination.storeBytes(
                    of: signedThunk,
                    as: UnsafeRawPointer.self
                )
                (destination + MemoryLayout<UInt>.size).storeBytes(
                    of: UnsafeRawPointer(RetainedRuntimeState.retain(state)),
                    as: UnsafeRawPointer.self
                )
            case .unsupported(let message):
                preconditionFailure(message)
        }
    }
}
