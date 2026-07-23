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

func tdSwiftInvokeAsyncFunction(
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
    func tdSwiftInvokeAsyncWitness(
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
    func tdSwiftInvokeAsyncWitness(
        _ function: UnsafeRawPointer,
        _ selfValue: UnsafeRawPointer,
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        _ isThrowing: Bool,
        _ stackArguments: UnsafePointer<TDAsyncWitnessStackArguments>?
    ) async
#endif

func decodeDirectResult(
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
func hasOnlyDynamicallySupportedExtendedFlags(
    _ metadata: FunctionMetadata
) -> Bool {
    let typedThrowsFlag = UInt32(0x1)
    return metadata.rawExtendedFlags.map { $0 & ~typedThrowsFlag == 0 } ?? true
}

func isDynamicFunctionAsync(_ metadata: FunctionMetadata) -> Bool {
    metadata.flags.bits & 0x2000_0000 != 0
}

func typedThrowingFunctionRuntimeUnsupportedReason(
    _ metadata: FunctionMetadata
) -> String? {
    guard metadata.typedThrownErrorType != nil else { return nil }
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

func dynamicDirectTypedErrorUsesIndirectResultSlot(
    _ metadata: FunctionMetadata
) -> Bool {
    guard let errorType = metadata.typedThrownErrorType else { return false }
    return abiClassIsIndirect(abiClass(for: metadata.resultType, isReturn: true))
        || typedErrorLayoutRequiresIndirectSlot(
            abiClass(for: errorType, isReturn: true)
        )
}

/// Generic reabstraction lowers every nonempty typed error as `@error @out`.
/// A value may be directly returned in registers while still requiring this
/// distinct buffer in the generic function convention. Zero-size errors omit
/// the physical slot because there is no payload to initialize.
func dynamicGenericTypedErrorUsesIndirectResultSlot(
    _ metadata: FunctionMetadata
) -> Bool {
    guard let errorType = metadata.typedThrownErrorType else { return false }
    return dynamicDirectTypedErrorUsesIndirectResultSlot(metadata)
        || reflect(errorType).vwt.size > 0
}

func abiClassIsIndirect(_ abi: ABIClass) -> Bool {
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
    var rawExtendedFlags: UInt32? {
        guard let offset = extendedFlagsOffset else { return nil }
        return ptr.load(fromByteOffset: offset, as: UInt32.self)
    }

    var isIsolatedAny: Bool {
        rawExtendedFlags.map { $0 & 0xE == 0x2 } == true
    }

    var isNonisolatedNonsending: Bool {
        rawExtendedFlags.map { $0 & 0xE == 0x4 } == true
    }

    var typedThrownErrorType: Any.Type? {
        guard let offset = extendedFlagsOffset else { return nil }
        let extendedFlags = ptr.load(fromByteOffset: offset, as: UInt32.self)
        guard extendedFlags & 0x1 != 0 else { return nil }
        let thrownErrorOffset = alignedToPointer(
            offset + MemoryLayout<UInt32>.size
        )
        return ptr.load(
            fromByteOffset: thrownErrorOffset,
            as: Any.Type.self
        )
    }

    var globalActorType: Any.Type? {
        guard rawFlagsBits & 0x1000_0000 != 0 else { return nil }
        return unsafeBitCast(
            ptr.load(
                fromByteOffset: postDifferentiabilityOffset,
                as: UnsafeRawPointer.self
            ),
            to: Any.Type.self
        )
    }

    private var extendedFlagsOffset: Int? {
        guard rawFlagsBits & 0x8000_0000 != 0 else { return nil }
        var offset = postDifferentiabilityOffset
        if rawFlagsBits & 0x1000_0000 != 0 {
            offset += MemoryLayout<UInt>.size
        }
        return offset
    }

    private var postDifferentiabilityOffset: Int {
        var offset =
            3 * MemoryLayout<UInt>.size
            + flags.numParams * MemoryLayout<Any.Type>.size
        if flags.hasParamFlags {
            offset += flags.numParams * MemoryLayout<UInt32>.size
        }
        offset = alignedToPointer(offset)
        if rawFlagsBits & 0x0800_0000 != 0 {
            offset += MemoryLayout<UInt>.size
        }
        return offset
    }

    private var rawFlagsBits: UInt32 {
        UInt32(truncatingIfNeeded: flags.bits)
    }

    private func alignedToPointer(_ offset: Int) -> Int {
        (offset + MemoryLayout<UInt>.alignment - 1)
            & ~(MemoryLayout<UInt>.alignment - 1)
    }
}
