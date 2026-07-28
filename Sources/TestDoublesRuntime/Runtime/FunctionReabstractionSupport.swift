import CTestDoublesTrampoline
import Echo
import EchoRuntimeReflection
import Foundation
import TestDoublesRuntimeMetadata

// WASI has neither this trampoline's assembly nor executable memory for a
// fabricated veneer, so these three get real (unreachable-in-practice)
// bodies here instead of an externally-linked entry point -- a real Swift
// async body lets the compiler synthesize the ABI thunk itself.
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
    _ function: FunctionTypeInfo
) -> Bool {
    // Keep this exact bit comparison as a fail-closed gate for future ABI
    // extensions that Echo cannot interpret yet. The semantic reflection
    // surface retains the raw discriminator precisely for this rejection.
    let supportedBits: UInt32 = function.effects.isTypedThrows ? 0x1 : 0
    return function.effects.rawExtendedFlags ?? 0 == supportedBits
        && runtimeFunctionHasSendingResult(function) == false
}

/// Exact compiler reabstraction can preserve the extended effects whose
/// lowered thunk spelling is complete enough to match against runtime
/// metadata. Future isolation values and inverted protocol requirements stay
/// fail-closed even if an incidentally same-shaped thunk is present.
package func hasOnlyExactlyMatchableExtendedFlags(
    _ function: FunctionTypeInfo
) -> Bool {
    let rawFlags = function.effects.rawExtendedFlags ?? 0
    let knownMask: UInt32 = 0x1 | 0xE | 0x10
    guard rawFlags & ~knownMask == 0 else { return false }
    switch rawFlags & 0xE {
        case 0, 0x2, 0x4:
            return true
        default:
            return false
    }
}

/// Whether `function`'s own compiler-emitted type spelling shows a
/// `throws(ErrorType)` clause, independent of the extended-flags metadata
/// Echo reads back.
///
/// Observed on watchOS and visionOS Simulator for a closure that combines a
/// `sending` parameter with a `sending` result (e.g. `@Sendable (sending
/// String) -> sending String`): Echo's `isTypedThrows` bit reads back `true`
/// for a closure that never declared `throws` at all, and the trailing
/// `typedErrorType` pointer that a genuine typed-throws closure would store
/// right after it is then read from the wrong offset, producing an address
/// that crashes the process when something dereferences it (`FunctionType
/// Metadata.getMetadata(at:)` reading e.g. address `0x10`). The demangled
/// spelling is derived from the mangled type name string instead of that
/// trailing metadata, so it stays trustworthy even when the flags word does
/// not.
private func demangledSpellingConfirmsTypedThrows(
    _ function: FunctionTypeInfo
) -> Bool {
    guard
        case .function(let syntax)? = DemangledTypeSyntax(
            String(reflecting: function.type)
        )
    else {
        return false
    }
    return syntax.effects.thrownError != nil
}

package func typedThrowingFunctionRuntimeUnsupportedReason(
    _ function: FunctionTypeInfo
) -> String? {
    guard function.effects.isTypedThrows else { return nil }
    guard demangledSpellingConfirmsTypedThrows(function) else {
        return "Typed-throws closure error metadata could not be resolved safely."
    }

    // Echo's typed-throws field is not a usable `Any.Type` on the Swift 6.3
    // Linux x86_64 release runtime. Reading it can produce an invalid metadata
    // pointer during bridge planning, so reject the unsupported ABI before any
    // reflection rather than letting the trampoline crash.
    #if os(Linux) && arch(x86_64)
        return "Typed-throws closure values are unavailable on Linux x86_64 because the Swift runtime does not expose their error metadata in a stable ABI form."
    #else
        guard function.effects.typedErrorType != nil else {
            return "Typed-throws closure error metadata could not be resolved safely."
        }
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
    #endif
}

package func dynamicDirectTypedErrorUsesIndirectResultSlot(
    _ function: FunctionTypeInfo
) -> Bool {
    guard let errorType = function.effects.typedErrorType else { return false }
    return abiClassIsIndirect(abiClass(for: function.resultType, isReturn: true))
        || typedErrorLayoutRequiresIndirectSlot(
            abiClass(for: errorType, isReturn: true)
        )
}

/// Generic reabstraction lowers every nonempty typed error as `@error @out`.
/// A value may be directly returned in registers while still requiring this
/// distinct buffer in the generic function convention. Zero-size errors omit
/// the physical slot because there is no payload to initialize.
package func dynamicGenericTypedErrorUsesIndirectResultSlot(
    _ function: FunctionTypeInfo
) -> Bool {
    guard let errorType = function.effects.typedErrorType else { return false }
    return dynamicDirectTypedErrorUsesIndirectResultSlot(function)
        || ValueLayoutInfo(reflecting: errorType).size > 0
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
