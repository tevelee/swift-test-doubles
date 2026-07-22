import CTestDoublesTrampoline
import Echo

func canDynamicallyInitializeFunctionResult(
    _ metadata: FunctionMetadata
) -> Bool {
    dynamicFunctionReturnBridgeUnsupportedReason(metadata) == nil
}

func dynamicFunctionReturnBridgeUnsupportedReason(
    _ metadata: FunctionMetadata
) -> String? {
    FunctionBridgePlan(metadata).unsupportedReason(for: .genericToDirect)
}

func initializeDynamicFunctionResult(
    _ source: UnsafeMutableRawPointer,
    metadata: FunctionMetadata,
    discriminator: UInt16,
    at destination: UnsafeMutableRawPointer
) {
    let context = DynamicFunctionReturnContext(
        source: source,
        metadata: metadata
    )
    let entry: UnsafeRawPointer
    let signedEntry: UnsafeRawPointer
    if isDynamicFunctionAsync(metadata) {
        guard let descriptor = td_swift_dynamic_async_function_descriptor()
        else {
            preconditionFailure(
                "[TestDoubles] Missing dynamic async function descriptor."
            )
        }
        entry = UnsafeRawPointer(descriptor)
        signedEntry =
            td_sign_async_function_pointer(entry, discriminator)
            .map(UnsafeRawPointer.init) ?? entry
    } else {
        entry = unsafeBitCast(
            td_swift_dynamic_function_entry as @convention(c) () -> Void,
            to: UnsafeRawPointer.self
        )
        signedEntry =
            td_sign_function_pointer(entry, discriminator)
            .map(UnsafeRawPointer.init) ?? entry
    }
    destination.storeBytes(of: signedEntry, as: UnsafeRawPointer.self)
    (destination + MemoryLayout<UInt>.size).storeBytes(
        of: UnsafeRawPointer(Unmanaged.passRetained(context).toOpaque()),
        as: UnsafeRawPointer.self
    )
}

func prepareDynamicAsyncFunctionReturn(
    _ frame: TrampolineCallFrame
) -> TDAsyncTrampolineResult {
    guard
        let contextAddress = UnsafeRawPointer(
            bitPattern: frame.swiftSelfAddress
        )
    else {
        preconditionFailure(
            "[TestDoubles] Dynamic async function call has no context."
        )
    }
    let context = Unmanaged<DynamicFunctionReturnContext>
        .fromOpaque(contextAddress)
        .takeUnretainedValue()
    let state = DynamicAsyncFunctionReturnState(
        context: context,
        frame: frame
    )
    return TDAsyncTrampolineResult(
        state: Unmanaged.passRetained(state).toOpaque(),
        stackAdjustment: context.directStackAdjustment
    )
}

@_cdecl("td_swift_dynamic_function_handler")
func tdSwiftDynamicFunctionHandler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) {
    guard let rawFrame else {
        preconditionFailure("[TestDoubles] Dynamic function call has no frame.")
    }
    let frame = TrampolineCallFrame(rawFrame)
    guard
        let contextAddress = UnsafeRawPointer(
            bitPattern: frame.swiftSelfAddress
        )
    else {
        preconditionFailure("[TestDoubles] Dynamic function call has no context.")
    }
    let context = Unmanaged<DynamicFunctionReturnContext>
        .fromOpaque(contextAddress)
        .takeUnretainedValue()
    context.invoke(into: frame)
}

private final class DynamicFunctionReturnContext: @unchecked Sendable {
    private let function: UnsafeRawPointer
    private let functionContext: UnsafeRawPointer?
    private let metadata: FunctionMetadata
    private let plan: FunctionBridgePlan
    private var parameterTypes: [Any.Type] { plan.parameterTypes }
    private var typedErrorType: Any.Type? { plan.typedErrorType }
    private var typedErrorLayout: ABIClass? { plan.typedErrorLayout }
    private var directTypedErrorUsesIndirectResultSlot: Bool {
        plan.directTypedErrorUsesIndirectResultSlot
    }
    private var genericTypedErrorUsesIndirectResultSlot: Bool {
        plan.genericTypedErrorUsesIndirectResultSlot
    }
    private var isAsync: Bool { plan.isAsync }
    private var asyncDirectResultUsesGeneralPurposeSlot: Bool {
        plan.asyncDirectResultUsesGeneralPurposeSlot
    }
    fileprivate var directStackAdjustment: UInt64 {
        UInt64(
            dynamicAsyncStackAdjustmentByteCount(
                usesStackArgument:
                    plan.directArgumentPlan?.usesStackArgument == true
            )
        )
    }

    init(source: UnsafeMutableRawPointer, metadata: FunctionMetadata) {
        guard let function = source.load(as: UnsafeRawPointer?.self) else {
            preconditionFailure(
                "[TestDoubles] Generic function value \(metadata.type) has no entry point."
            )
        }
        self.function = function
        functionContext = (source + MemoryLayout<UInt>.size)
            .load(as: UnsafeRawPointer?.self)
        self.metadata = metadata
        plan = FunctionBridgePlan(metadata)
        if let functionContext {
            td_swift_retain(functionContext)
        }
    }

    deinit {
        if let functionContext {
            td_swift_release(functionContext)
        }
    }

    func invoke(into frame: TrampolineCallFrame) {
        let decoded = decodeArguments(from: frame)
        encode(
            invokeGenericFunction(decoded.values),
            decoded: decoded,
            into: frame
        )
    }

    func decodeArguments(from frame: TrampolineCallFrame) -> DecodedArguments {
        RuntimeArgumentDecoder.decodeDynamicFunctionArguments(
            parameterTypes,
            typedErrorUsesIndirectResultSlot:
                directTypedErrorUsesIndirectResultSlot,
            initialGeneralPurposeOffset:
                asyncDirectResultUsesGeneralPurposeSlot ? 1 : 0,
            from: frame
        )
    }

    func invokeAsync(
        _ arguments: [Any]
    ) async -> DynamicGenericFunctionOutcome {
        await invokeGenericAsyncFunction(arguments)
    }

    func encode(
        _ outcome: DynamicGenericFunctionOutcome,
        decoded: DecodedArguments,
        into frame: TrampolineCallFrame
    ) {
        switch outcome {
            case .success(let result):
                RuntimeResultEncoder.encodeDynamicFunctionReturn(
                    result,
                    expectedType: metadata.resultType,
                    isAsync: isAsync,
                    into: frame
                )
                if metadata.flags.throws {
                    frame.storeReturnError(0)
                }
            case .failure(let error):
                if let typedErrorType, let typedErrorLayout {
                    RuntimeResultEncoder.encodeDynamicTypedFunctionFailure(
                        error,
                        expectedType: typedErrorType,
                        layout: typedErrorLayout,
                        destination: decoded.typedErrorDestination,
                        usesIndirectResultSlot:
                            directTypedErrorUsesIndirectResultSlot,
                        into: frame
                    )
                } else {
                    guard let error = error as? any Error else {
                        preconditionFailure(
                            "[TestDoubles] Dynamic function failure does not conform to Error."
                        )
                    }
                    RuntimeResultEncoder.encodeDynamicFunctionFailure(
                        error,
                        into: frame
                    )
                }
        }
    }

    private func invokeGenericFunction(
        _ arguments: [Any]
    ) -> DynamicGenericFunctionOutcome {
        precondition(arguments.count == parameterTypes.count)
        var argumentContainers = arguments.map(Echo.container(for:))
        let call = ManagedDynamicCall(
            resultType: metadata.resultType,
            errorType: typedErrorType
        )
        defer { _fixLifetime(arguments) }

        let frame = call.frame
        for index in argumentContainers.indices {
            frame.storeDynamicGeneralPurposeArgument(
                UInt(bitPattern: argumentContainers[index].projectValue()),
                at: index
            )
        }
        let hasResult = metadata.resultType != Void.self
        if hasResult {
            frame.storeIndirectResultAddress(UInt(bitPattern: call.result.storage))
        }
        if let error = call.error, genericTypedErrorUsesIndirectResultSlot {
            frame.storeDynamicGeneralPurposeArgument(
                UInt(bitPattern: error.storage),
                at: parameterTypes.count
            )
        }
        let discriminator = td_generic_function_discriminator(
            UInt16(parameterTypes.count),
            hasResult
        )
        td_swift_invoke_function(
            function,
            functionContext,
            discriminator,
            call.rawFrame
        )
        return outcome(from: call, hasResult: hasResult)
    }

    private func invokeGenericAsyncFunction(
        _ arguments: [Any]
    ) async -> DynamicGenericFunctionOutcome {
        precondition(arguments.count == parameterTypes.count)
        var argumentContainers = arguments.map(Echo.container(for:))
        let call = ManagedDynamicCall(
            resultType: metadata.resultType,
            errorType: typedErrorType
        )
        defer { _fixLifetime(arguments) }

        let frame = call.frame
        let hasResult = metadata.resultType != Void.self
        let initialGeneralPurposeOffset: Int
        if hasResult {
            let resultAddress = UInt(bitPattern: call.result.storage)
            frame.storeIndirectResultAddress(resultAddress)
            frame.storeDynamicGeneralPurposeArgument(resultAddress, at: 0)
            initialGeneralPurposeOffset = 1
        } else {
            initialGeneralPurposeOffset = 0
        }
        for index in argumentContainers.indices {
            frame.storeDynamicGeneralPurposeArgument(
                UInt(bitPattern: argumentContainers[index].projectValue()),
                at: initialGeneralPurposeOffset + index
            )
        }
        if let error = call.error, genericTypedErrorUsesIndirectResultSlot {
            frame.storeDynamicGeneralPurposeArgument(
                UInt(bitPattern: error.storage),
                at: initialGeneralPurposeOffset + parameterTypes.count
            )
        }
        let discriminator = td_generic_function_discriminator(
            UInt16(parameterTypes.count),
            hasResult
        )
        await tdSwiftInvokeAsyncFunction(
            function,
            functionContext,
            discriminator,
            call.rawFrame,
            metadata.flags.throws,
            plan.genericUsesStackArgument
        )
        return outcome(from: call, hasResult: hasResult)
    }

    private func outcome(
        from call: ManagedDynamicCall,
        hasResult: Bool
    ) -> DynamicGenericFunctionOutcome {
        let frame = call.frame
        if frame.returnedError != 0 {
            guard let typedErrorType, let typedErrorLayout, let errorBuffer = call.error
            else {
                return .failure(takeSwiftError(frame.returnedError))
            }
            if genericTypedErrorUsesIndirectResultSlot == false {
                decodeDirectResult(
                    typedErrorLayout,
                    frame: call.rawFrame,
                    into: errorBuffer.storage
                )
            }
            errorBuffer.markInitialized()
            let boxedError = FunctionReabstraction.boxDirectValue(
                type: typedErrorType,
                source: errorBuffer.storage
            )
            errorBuffer.destroyInitializedValue()
            return .failure(boxedError)
        }
        guard hasResult else { return .success(()) }

        call.result.markInitialized()
        let result = boxValue(
            type: metadata.resultType,
            source: call.result.storage
        )
        call.result.destroyInitializedValue()
        return .success(result)
    }
}

private final class DynamicAsyncFunctionReturnState:
    AsyncTrampolineDispatchState,
    @unchecked Sendable
{
    private var frame: TDCallFrame
    private let context: DynamicFunctionReturnContext
    private let decoded: DecodedArguments

    init(context: DynamicFunctionReturnContext, frame: TrampolineCallFrame) {
        self.context = context
        self.frame = frame.snapshot
        decoded = context.decodeArguments(from: frame)
    }

    func run() async {
        let outcome = await context.invokeAsync(decoded.values)
        withUnsafeMutablePointer(to: &frame) { pointer in
            context.encode(
                outcome,
                decoded: decoded,
                into: TrampolineCallFrame(pointer)
            )
        }
    }

    func finish(into frame: TrampolineCallFrame) {
        frame.restore(self.frame)
    }
}

private enum DynamicGenericFunctionOutcome: @unchecked Sendable {
    case success(Any)
    case failure(Any)
}
