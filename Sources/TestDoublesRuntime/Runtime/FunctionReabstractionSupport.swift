import CTestDoublesTrampoline
import Echo
import Foundation

// WASI has neither this trampoline's arm64/x86_64 assembly nor executable
// memory to publish a fabricated veneer into (witness veneer allocation
// always fails first there — see WitnessVeneerArena.c), so these three give
// themselves real, unreachable-in-practice bodies on that platform instead of
// only declaring an externally-linked entry point. A real Swift async
// function body lets the compiler synthesize the matching async ABI thunk
// itself, the same way td_swift_async_dispatch does in TrampolineHandler.swift,
// rather than requiring one to be hand-assembled.
#if os(WASI)
    @_silgen_name("td_swift_invoke_async_function")
    // swiftlint:disable:next unavailable_function
    private func tdSwiftInvokeAsyncFunctionWithoutStack(
        _ function: UnsafeRawPointer,
        _ context: UnsafeRawPointer?,
        _ discriminator: UInt16,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool
    ) async {
        fatalError("unreachable on wasm32-wasi")
    }
#else
    @_silgen_name("td_swift_invoke_async_function")
    private func tdSwiftInvokeAsyncFunctionWithoutStack(
        _ function: UnsafeRawPointer,
        _ context: UnsafeRawPointer?,
        _ discriminator: UInt16,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool
    ) async
#endif

#if os(WASI)
    @_silgen_name("td_swift_invoke_async_function_with_stack")
    // swiftlint:disable:next unavailable_function
    private func tdSwiftInvokeAsyncFunctionWithStack(
        _ function: UnsafeRawPointer,
        _ context: UnsafeRawPointer?,
        _ discriminator: UInt16,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool,
        _ firstRegisterPadding: UInt,
        _ secondRegisterPadding: UInt,
        _ thirdRegisterPadding: UInt,
        _ stackWord: UInt
    ) async {
        fatalError("unreachable on wasm32-wasi")
    }
#elseif arch(x86_64)
    @_silgen_name("td_swift_invoke_async_function_with_stack")
    private func tdSwiftInvokeAsyncFunctionWithStack(
        _ function: UnsafeRawPointer,
        _ context: UnsafeRawPointer?,
        _ discriminator: UInt16,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool,
        _ registerPadding: UInt,
        _ stackWord: UInt
    ) async
#else
    @_silgen_name("td_swift_invoke_async_function_with_stack")
    private func tdSwiftInvokeAsyncFunctionWithStack(
        _ function: UnsafeRawPointer,
        _ context: UnsafeRawPointer?,
        _ discriminator: UInt16,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool,
        _ firstRegisterPadding: UInt,
        _ secondRegisterPadding: UInt,
        _ thirdRegisterPadding: UInt,
        _ stackWord: UInt
    ) async
#endif

package func tdSwiftInvokeAsyncFunction(
    _ function: UnsafeRawPointer,
    _ context: UnsafeRawPointer?,
    _ discriminator: UInt16,
    _ frame: UnsafeMutablePointer<TDCallFrame>,
    _ isThrowing: Bool,
    _ hasStackArgument: Bool
) async {
    guard hasStackArgument else {
        await tdSwiftInvokeAsyncFunctionWithoutStack(
            function,
            context,
            discriminator,
            frame,
            isThrowing
        )
        return
    }

    let stackWord = TrampolineCallFrame(frame).outgoingStackWord
    #if arch(x86_64)
        await tdSwiftInvokeAsyncFunctionWithStack(
            function,
            context,
            discriminator,
            frame,
            isThrowing,
            0,
            stackWord
        )
    #else
        await tdSwiftInvokeAsyncFunctionWithStack(
            function,
            context,
            discriminator,
            frame,
            isThrowing,
            0,
            0,
            0,
            stackWord
        )
    #endif
}

#if os(WASI)
    @_silgen_name("td_swift_invoke_async_witness")
    // swiftlint:disable:next unavailable_function
    package func tdSwiftInvokeAsyncWitness(
        _ function: UnsafeRawPointer,
        _ selfValue: UnsafeRawPointer,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool,
        _ stackArguments: UnsafePointer<TDAsyncWitnessStackArguments>?
    ) async {
        fatalError("unreachable on wasm32-wasi")
    }
#else
    @_silgen_name("td_swift_invoke_async_witness")
    package func tdSwiftInvokeAsyncWitness(
        _ function: UnsafeRawPointer,
        _ selfValue: UnsafeRawPointer,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool,
        _ stackArguments: UnsafePointer<TDAsyncWitnessStackArguments>?
    ) async
#endif

package func decodeDirectResult(
    _ layout: ABIClass,
    frame: UnsafeMutablePointer<TDCallFrame>,
    into destination: UnsafeMutableRawPointer
) {
    let raw = UnsafeMutableRawPointer(frame)
    switch layout {
        case .void, .indirect:
            return
        case .floatingPoint:
            let value = raw.loadUnaligned(
                fromByteOffset: Int(TD_FRAME_RETURN_FP_OFFSET),
                as: UInt64.self
            )
            destination.storeBytes(of: value, as: UInt64.self)
        case .integer(let words):
            for index in 0 ..< words {
                let value = raw.loadUnaligned(
                    fromByteOffset: Int(TD_FRAME_RETURN_GP_OFFSET) + index * 8,
                    as: UInt.self
                )
                destination.storeBytes(
                    of: value,
                    toByteOffset: index * 8,
                    as: UInt.self
                )
            }
        case .aggregate(let parts):
            var generalPurpose = 0
            var floatingPoint = 0
            for part in parts {
                let value: UInt64
                switch part.register {
                    case .gp:
                        value = UInt64(
                            raw.loadUnaligned(
                                fromByteOffset: Int(TD_FRAME_RETURN_GP_OFFSET)
                                    + generalPurpose * 8,
                                as: UInt.self
                            )
                        )
                        generalPurpose += 1
                    case .fp:
                        value = raw.loadUnaligned(
                            fromByteOffset: Int(TD_FRAME_RETURN_FP_OFFSET)
                                + floatingPoint * 8,
                            as: UInt64.self
                        )
                        floatingPoint += 1
                }
                part.store(value, into: destination)
            }
    }
}

/// Extended function metadata currently assigns bit zero to a concrete typed
/// error result. The dynamic bridge can reproduce that transport, but must
/// continue to reject every other extended flag because those bits alter
/// isolation, ownership, or invocation semantics.
package func hasOnlyDynamicallySupportedExtendedFlags(
    _ metadata: FunctionMetadata
) -> Bool {
    guard let flags = metadata.extendedFlags else { return true }

    let invertedProtocols = flags.invertedProtocols
    guard flags.isIsolatedAny == false,
        flags.isNonIsolatedNonsending == false,
        flags.hasSendingResult == false,
        invertedProtocols.isEmpty,
        invertedProtocols.hasUnknownProtocols == false
    else {
        return false
    }

    // Echo exposes the currently understood semantics above. Keep this exact
    // bit comparison as a fail-closed gate for reserved flags and future ABI
    // extensions that Echo cannot name yet.
    let supportedBits: UInt32 = flags.isTypedThrows ? 0x1 : 0
    return flags.bits == supportedBits
}

package func isDynamicFunctionAsync(_ metadata: FunctionMetadata) -> Bool {
    metadata.flags.isAsync
}

package func typedThrowingFunctionRuntimeUnsupportedReason(
    _ metadata: FunctionMetadata
) -> String? {
    guard metadata.thrownErrorType != nil else { return nil }
    guard
        #available(macOS 15,
        iOS 18,
        macCatalyst 18,
        tvOS 18,
        visionOS 2,
        watchOS 11,
        *)
    else {
        return "Typed-throws closure values require macOS 15, iOS 18, Mac Catalyst 18, tvOS 18, visionOS 2, or watchOS 11."
    }
    return nil
}

package func dynamicDirectTypedErrorUsesIndirectResultSlot(
    _ metadata: FunctionMetadata
) -> Bool {
    guard let errorType = metadata.thrownErrorType else { return false }
    return abiClassIsIndirect(abiClass(for: metadata.resultType, isReturn: true))
        || typedErrorLayoutRequiresIndirectSlot(
            abiClass(for: errorType, isReturn: true)
        )
}

/// Generic reabstraction lowers every nonempty typed error as `@error @out`.
/// A value may be directly returned in registers while still requiring this
/// distinct buffer in the generic function convention. Zero-size errors omit
/// the physical slot because there is no payload to initialize.
package func dynamicGenericTypedErrorUsesIndirectResultSlot(
    _ metadata: FunctionMetadata
) -> Bool {
    guard let errorType = metadata.thrownErrorType else { return false }
    return dynamicDirectTypedErrorUsesIndirectResultSlot(metadata)
        || reflect(errorType).vwt.size > 0
}

package func abiClassIsIndirect(_ abi: ABIClass) -> Bool {
    if case .indirect = abi { return true }
    return false
}

private func typedErrorLayoutRequiresIndirectSlot(_ abi: ABIClass) -> Bool {
    switch abi {
        case .void, .integer:
            return false
        case .floatingPoint, .indirect:
            return true
        case .aggregate(let parts):
            return parts.contains { $0.register == .fp }
    }
}

final class ReabstractionContext: @unchecked Sendable {
    // Ordinary compiler-emitted partial-apply forwarders load the first two
    // words. `@isolated(any)` forwarders load four words: the isolation pair
    // followed by the underlying function pair. The direct isolated closure's
    // context already owns that compiler-created four-word payload.
    let first: UnsafeRawPointer?
    let second: UnsafeRawPointer?
    let third: UnsafeRawPointer?
    let fourth: UnsafeRawPointer?
    let retainedSourceContext: UnsafeRawPointer?

    init(
        function: UnsafeRawPointer,
        context: UnsafeRawPointer?,
        isIsolatedAny: Bool
    ) {
        if isIsolatedAny {
            guard let context else {
                preconditionFailure(
                    "[TestDoubles] An @isolated(any) closure has no isolation context."
                )
            }
            first = (context + 2 * MemoryLayout<UInt>.size)
                .load(as: UnsafeRawPointer?.self)
            second = (context + 3 * MemoryLayout<UInt>.size)
                .load(as: UnsafeRawPointer?.self)
            third = function
            fourth = context
        } else {
            first = function
            second = context
            third = nil
            fourth = nil
        }
        retainedSourceContext = context
        if let context {
            td_swift_retain(context)
        }
    }

    deinit {
        if let context = retainedSourceContext {
            td_swift_release(context)
        }
    }

    func validateStoredLayout() {
        let object = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        precondition(
            (object + 2 * MemoryLayout<UInt>.size)
                .load(as: UnsafeRawPointer?.self) == first
                && (object + 3 * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer?.self) == second
                && (object + 4 * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer?.self) == third
                && (object + 5 * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer?.self) == fourth,
            "[TestDoubles] Swift changed native partial-apply context layout."
        )
    }
}

func normalizedThunkName(_ value: String) -> String {
    let asyncPrefix = "async function pointer to "
    let withoutAsyncPrefix =
        value.hasPrefix(asyncPrefix)
        ? String(value.dropFirst(asyncPrefix.count))
        : value
    guard let suffix = withoutAsyncPrefix.range(of: " with unmangled suffix ")
    else { return withoutAsyncPrefix }
    return String(withoutAsyncPrefix[..<suffix.lowerBound])
}

func demangleReabstractionSymbol(_ mangledName: String) -> String {
    RuntimeSymbols.demangle(mangledName)
}

extension FunctionMetadata {
    /// Compatibility spelling for the isolated-any query used by the existing
    /// reabstraction implementation.
    var isIsolatedAny: Bool {
        extendedFlags?.isIsolatedAny == true
    }

    /// Compatibility spelling for the nonisolated-nonsending query used by
    /// the existing function-pointer authentication implementation.
    var isNonisolatedNonsending: Bool {
        extendedFlags?.isNonIsolatedNonsending == true
    }

    /// Compatibility spelling for the typed-throws result consumed by the
    /// existing reabstraction implementation.
    var typedThrownErrorType: Any.Type? {
        thrownErrorType
    }
}
