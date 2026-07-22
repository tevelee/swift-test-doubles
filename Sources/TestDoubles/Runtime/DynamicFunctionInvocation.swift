import CTestDoublesTrampoline
import Echo

func canDynamicallyBoxFunctionArgument(
    _ metadata: FunctionMetadata
) -> Bool {
    dynamicFunctionBridgeUnsupportedReason(metadata) == nil
}

func dynamicFunctionBridgeUnsupportedReason(
    _ metadata: FunctionMetadata
) -> String? {
    FunctionBridgePlan(metadata).unsupportedReason(for: .directToGeneric)
}

private enum DynamicTypedInvocationOutcome<Result, Failure: Error> {
    case success(Result)
    case failure(Failure)
}

final class DynamicFunctionInvocation: @unchecked Sendable {
    let plan: FunctionBridgePlan
    var parameterTypes: [Any.Type] { plan.parameterTypes }
    let typedErrorType: (any Error.Type)?

    private let function: UnsafeRawPointer
    private let context: UnsafeRawPointer?
    private let discriminator: UInt16
    private var typedErrorUsesIndirectResultSlot: Bool {
        plan.directTypedErrorUsesIndirectResultSlot
    }

    init(
        function: UnsafeRawPointer,
        context: UnsafeRawPointer?,
        discriminator: UInt16,
        plan: FunctionBridgePlan
    ) {
        self.function = function
        self.context = context
        self.discriminator = discriminator
        self.plan = plan
        if let typedErrorType = plan.typedErrorType {
            guard let errorType = typedErrorType as? any Error.Type else {
                preconditionFailure(
                    "[TestDoubles] Typed closure error \(typedErrorType) does not conform to Error."
                )
            }
            self.typedErrorType = errorType
        } else {
            self.typedErrorType = nil
        }
        if let context {
            td_swift_retain(context)
        }
    }

    deinit {
        if let context {
            td_swift_release(context)
        }
    }

    func call<Result>(
        _ arguments: [Any],
        returning resultType: Result.Type
    ) -> Result {
        withInvocation(arguments, returning: resultType) {
            result, _, frame in
            precondition(
                frame.returnedError == 0,
                "[TestDoubles] A nonthrowing dynamic closure returned a Swift error."
            )
            return moveDirectResult(from: result, as: resultType)
        }
    }

    func callThrowing<Result>(
        _ arguments: [Any],
        returning resultType: Result.Type
    ) throws -> Result {
        try withInvocation(arguments, returning: resultType) {
            result, _, frame in
            if frame.returnedError != 0 {
                throw takeSwiftError(frame.returnedError)
            }
            return moveDirectResult(from: result, as: resultType)
        }
    }

    func callTyped<Failure: Error, Result>(
        _ arguments: [Any],
        throwing failureType: Failure.Type,
        returning resultType: Result.Type
    ) throws(Failure) -> Result {
        let outcome: DynamicTypedInvocationOutcome<Result, Failure> =
            withInvocation(
                arguments,
                returning: resultType,
                typedErrorType: failureType
            ) { result, error, frame in
                if frame.returnedError != 0 {
                    guard let error else {
                        preconditionFailure(
                            "[TestDoubles] A typed closure returned no error storage."
                        )
                    }
                    return .failure(
                        error.moveInitializedValue(as: Failure.self)
                    )
                }
                return .success(
                    moveDirectResult(from: result, as: resultType)
                )
            }
        switch outcome {
            case .success(let result): return result
            case .failure(let error): throw error
        }
    }

    func callAsync<Result>(
        _ arguments: [Any],
        returning resultType: Result.Type
    ) async -> Result {
        await withAsyncInvocation(arguments, returning: resultType) {
            result, _, frame in
            precondition(
                frame.returnedError == 0,
                "[TestDoubles] A nonthrowing dynamic async closure returned a Swift error."
            )
            return moveDirectResult(from: result, as: resultType)
        }
    }

    func callAsyncThrowing<Result>(
        _ arguments: [Any],
        returning resultType: Result.Type
    ) async throws -> Result {
        try await withAsyncInvocation(
            arguments,
            returning: resultType,
            isThrowing: true
        ) {
            result, _, frame in
            if frame.returnedError != 0 {
                throw takeSwiftError(frame.returnedError)
            }
            return moveDirectResult(from: result, as: resultType)
        }
    }

    func callAsyncTyped<Failure: Error, Result>(
        _ arguments: [Any],
        throwing failureType: Failure.Type,
        returning resultType: Result.Type
    ) async throws(Failure) -> Result {
        let outcome: DynamicTypedInvocationOutcome<Result, Failure> =
            await withAsyncInvocation(
                arguments,
                returning: resultType,
                typedErrorType: failureType,
                isThrowing: true
            ) { result, error, frame in
                if frame.returnedError != 0 {
                    guard let error else {
                        preconditionFailure(
                            "[TestDoubles] A typed async closure returned no error storage."
                        )
                    }
                    return .failure(
                        error.moveInitializedValue(as: Failure.self)
                    )
                }
                return .success(
                    moveDirectResult(from: result, as: resultType)
                )
            }
        switch outcome {
            case .success(let result): return result
            case .failure(let error): throw error
        }
    }

    private func withInvocation<Result, Output>(
        _ arguments: [Any],
        returning _: Result.Type,
        typedErrorType: Any.Type? = nil,
        body: (
            ManagedValueBuffer,
            ManagedValueBuffer?,
            TrampolineCallFrame
        ) throws -> Output
    ) rethrows -> Output {
        precondition(arguments.count == parameterTypes.count)
        let layouts = plan.directArgumentLayouts!
        let prepared = zip(arguments, parameterTypes).map {
            PreparedDirectArgument(value: $0.0, type: $0.1)
        }
        let call = ManagedDynamicCall(
            resultType: Result.self,
            errorType: typedErrorType
        )
        defer { _fixLifetime(prepared) }

        let frame = call.frame
        let nextGeneralPurpose = encodeDynamicArguments(
            prepared,
            layouts: layouts,
            into: frame
        )
        let resultLayout = plan.resultLayout
        if case .indirect = resultLayout {
            frame.storeIndirectResultAddress(UInt(bitPattern: call.result.storage))
        } else {
            call.result.zeroBorrowedBytes()
        }
        if let error = call.error, typedErrorUsesIndirectResultSlot {
            frame.storeDynamicGeneralPurposeArgument(
                UInt(bitPattern: error.storage),
                at: nextGeneralPurpose
            )
        }
        td_swift_invoke_function(function, context, discriminator, call.rawFrame)
        if frame.returnedError == 0 {
            decodeDirectResult(
                resultLayout,
                frame: call.rawFrame,
                into: call.result.storage
            )
            call.result.markInitialized()
        } else if let error = call.error, typedErrorUsesIndirectResultSlot == false {
            let errorLayout = plan.typedErrorLayout!
            decodeDirectResult(
                errorLayout,
                frame: call.rawFrame,
                into: error.storage
            )
            error.markInitialized()
        } else if let error = call.error {
            error.markInitialized()
        }
        return try body(call.result, call.error, frame)
    }

    private func withAsyncInvocation<Result, Output>(
        _ arguments: [Any],
        returning _: Result.Type,
        typedErrorType: Any.Type? = nil,
        isThrowing: Bool = false,
        body: (
            ManagedValueBuffer,
            ManagedValueBuffer?,
            TrampolineCallFrame
        ) throws -> Output
    ) async rethrows -> Output {
        precondition(arguments.count == parameterTypes.count)
        let layouts = plan.directArgumentLayouts!
        let prepared = zip(arguments, parameterTypes).map {
            PreparedDirectArgument(value: $0.0, type: $0.1)
        }
        let call = ManagedDynamicCall(
            resultType: Result.self,
            errorType: typedErrorType
        )
        defer { _fixLifetime(prepared) }

        let frame = call.frame
        let resultLayout = plan.resultLayout
        let initialGeneralPurposeOffset: Int
        if case .indirect = resultLayout {
            let resultAddress = UInt(bitPattern: call.result.storage)
            frame.storeIndirectResultAddress(resultAddress)
            frame.storeDynamicGeneralPurposeArgument(resultAddress, at: 0)
            initialGeneralPurposeOffset = 1
        } else {
            call.result.zeroBorrowedBytes()
            initialGeneralPurposeOffset = 0
        }
        let nextGeneralPurpose = encodeDynamicArguments(
            prepared,
            layouts: layouts,
            initialGeneralPurposeOffset: initialGeneralPurposeOffset,
            into: frame
        )
        if let error = call.error, typedErrorUsesIndirectResultSlot {
            frame.storeDynamicGeneralPurposeArgument(
                UInt(bitPattern: error.storage),
                at: nextGeneralPurpose
            )
        }
        await tdSwiftInvokeAsyncFunction(
            function,
            context,
            discriminator,
            call.rawFrame,
            isThrowing,
            plan.directArgumentPlan!.usesStackArgument
        )
        if frame.returnedError == 0 {
            decodeDirectResult(
                resultLayout,
                frame: call.rawFrame,
                into: call.result.storage
            )
            call.result.markInitialized()
        } else if let error = call.error, typedErrorUsesIndirectResultSlot == false {
            let errorLayout = plan.typedErrorLayout!
            decodeDirectResult(
                errorLayout,
                frame: call.rawFrame,
                into: error.storage
            )
            error.markInitialized()
        } else if let error = call.error {
            error.markInitialized()
        }
        return try body(call.result, call.error, frame)
    }
}

private final class PreparedDirectArgument: @unchecked Sendable {
    let buffer: ManagedValueBuffer

    var storage: UnsafeMutableRawPointer { buffer.storage }

    init(value: Any, type: Any.Type) {
        buffer = ManagedValueBuffer(
            type: type,
            minimumByteCount: 16
        )
        buffer.zeroBorrowedBytes()
        RuntimeResultEncoder.initializeDirectValue(
            value,
            expectedType: type,
            to: buffer.storage
        )
        buffer.markInitialized()
    }
}

private func encodeDynamicArguments(
    _ arguments: [PreparedDirectArgument],
    layouts: [ABIClass],
    initialGeneralPurposeOffset: Int = 0,
    into frame: TrampolineCallFrame
) -> Int {
    var generalPurpose = initialGeneralPurposeOffset
    var floatingPoint = 0
    for (argument, layout) in zip(arguments, layouts) {
        switch layout {
            case .void:
                break
            case .floatingPoint:
                let value = argument.storage.loadUnaligned(as: UInt64.self)
                frame.storeFloatingPointArgument(value, at: floatingPoint)
                floatingPoint += 1
            case .integer(let words):
                for word in 0 ..< words {
                    let value = argument.storage.loadUnaligned(
                        fromByteOffset: word * MemoryLayout<UInt>.size,
                        as: UInt.self
                    )
                    frame.storeDynamicGeneralPurposeArgument(
                        value,
                        at: generalPurpose
                    )
                    generalPurpose += 1
                }
            case .aggregate(let parts):
                for part in parts {
                    switch part.register {
                        case .gp:
                            frame.storeDynamicGeneralPurposeArgument(
                                UInt(part.load(from: argument.storage)),
                                at: generalPurpose
                            )
                            generalPurpose += 1
                        case .fp:
                            frame.storeFloatingPointArgument(
                                part.load(from: argument.storage),
                                at: floatingPoint
                            )
                            floatingPoint += 1
                    }
                }
            case .indirect:
                frame.storeDynamicGeneralPurposeArgument(
                    UInt(bitPattern: argument.storage),
                    at: generalPurpose
                )
                generalPurpose += 1
        }
    }
    return generalPurpose
}

private func moveDirectResult<Result>(
    from buffer: ManagedValueBuffer,
    as _: Result.Type
) -> Result {
    let metadata = reflect(Result.self)
    guard
        metadata is FunctionMetadata
            || FunctionReabstraction.requiresStructuralReabstraction(Result.self)
    else {
        return buffer.moveInitializedValue(as: Result.self)
    }
    let value = FunctionReabstraction.boxDirectValue(
        type: Result.self,
        source: buffer.storage
    )
    buffer.destroyInitializedValue()
    guard let result = value as? Result else {
        preconditionFailure(
            "[TestDoubles] Dynamic closure result did not preserve \(Result.self)."
        )
    }
    return result
}

func takeSwiftError(_ address: UInt) -> any Error {
    guard let errorObject = UnsafeRawPointer(bitPattern: address) else {
        preconditionFailure("[TestDoubles] Dynamic closure returned an invalid error.")
    }
    var scratch: UnsafeMutableRawPointer?
    var extracted = TDSwiftErrorValue(
        value: nil,
        type: nil,
        witnessTable: nil
    )
    td_swift_get_error_value(errorObject, &scratch, &extracted)
    defer { td_swift_error_release(errorObject) }
    guard let value = extracted.value, let type = extracted.type else {
        preconditionFailure("[TestDoubles] Swift returned an empty error object.")
    }
    let runtimeType = unsafeBitCast(type, to: Any.Type.self)
    let boxed = boxValue(
        type: runtimeType,
        source: UnsafeMutableRawPointer(mutating: value)
    )
    guard let error = boxed as? any Error else {
        preconditionFailure(
            "[TestDoubles] Dynamic closure error \(runtimeType) does not conform to Error."
        )
    }
    return error
}

func safeFunctionParameterTypes(_ metadata: FunctionMetadata) -> [Any.Type] {
    guard metadata.flags.numParams > 0 else { return [] }
    return metadata.paramTypes
}
