import CTestDoublesTrampoline
import Echo
import Foundation

@_cdecl("td_swift_trampoline_handler")
func td_swift_trampoline_handler(_ rawFrame: UnsafeMutablePointer<TDCallFrame>?) {
    guard let rawFrame else { return }
    RuntimeTrampolineHandler.handle(rawFrame)
}

@_cdecl("td_swift_async_trampoline_handler")
func td_swift_async_trampoline_handler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) -> UnsafeMutableRawPointer? {
    guard let rawFrame else { return nil }
    return RuntimeTrampolineHandler.prepareAsync(rawFrame)
}

@_silgen_name("td_swift_async_dispatch")
func td_swift_async_dispatch(_ rawState: UnsafeMutableRawPointer) async {
    await RuntimeTrampolineHandler.dispatchAsync(rawState)
}

@_cdecl("td_swift_async_dispatch_finish")
func td_swift_async_dispatch_finish(
    _ rawState: UnsafeMutableRawPointer?,
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) {
    guard let rawState, let rawFrame else { return }
    RuntimeTrampolineHandler.finishAsync(rawState, into: rawFrame)
}

private enum RuntimeTrampolineHandler {
    /// Retained by the assembly bridge while the handler is suspended. A state
    /// belongs to one invocation: the caller task mutates it, then the completion
    /// functlet consumes the retain only after `dispatchAsync` has returned.
    private final class AsyncDispatchState: @unchecked Sendable {
        var frame: TDCallFrame
        let method: MethodDescriptor
        let args: [Any]
        let handler: ([Any]) async throws -> Any

        init(
            frame: TDCallFrame,
            method: MethodDescriptor,
            args: [Any],
            handler: @escaping ([Any]) async throws -> Any
        ) {
            self.frame = frame
            self.method = method
            self.args = args
            self.handler = handler
        }

        func run() async {
            do {
                let result = try await handler(args)
                withUnsafeMutablePointer(to: &frame) { frame in
                    frame.storeWord(0, at: TDFrame.returnError)
                    RuntimeTrampolineHandler.encodeReturn(result, for: method, into: frame)
                }
            } catch {
                guard method.isThrowing else {
                    fatalError("[TestDoubles] A nonthrowing async stub handler threw \(error).")
                }
                withUnsafeMutablePointer(to: &frame) { frame in
                    frame.zeroReturn()
                    frame.storeWord(swiftErrorPointer(error), at: TDFrame.returnError)
                }
            }
        }
    }

    static func handle(_ frame: UnsafeMutablePointer<TDCallFrame>) {
        let slot = Int(frame.loadWord(at: TDFrame.slot))
        guard let recorder = findRecorder(in: frame) else {
            fatalError("[TestDoubles] Trampoline could not resolve recorder for witness call at slot \(slot).")
        }
        guard let method = recorder.runtimeMethod(for: slot) else {
            fatalError("[TestDoubles] No method descriptor registered for witness slot \(slot).")
        }
        let args = decodeArguments(for: method, from: frame)
        handle(frame, recorder: recorder, method: method, args: args)
    }

    private static func handle(
        _ frame: UnsafeMutablePointer<TDCallFrame>,
        recorder: StubRecorder,
        method: MethodDescriptor,
        args: [Any]
    ) {
        let result: Any
        do {
            result = try recorder.dispatch(method: method, args: args)
            if method.isThrowing || method.isAsync {
                frame.storeWord(0, at: TDFrame.returnError)
            } else {
                frame.storeWord(frame.loadWord(at: TDFrame.swiftError), at: TDFrame.returnError)
            }
        } catch {
            guard method.isThrowing else {
                fatalError("[TestDoubles] A nonthrowing stub handler threw \(error).")
            }
            frame.storeWord(swiftErrorPointer(error), at: TDFrame.returnError)
            return
        }

        if recorder.mode == .normal {
            encodeReturn(result, for: method, into: frame)
        } else {
            encodeRecordingPlaceholder(for: method, args: args, into: frame)
        }
    }

    static func prepareAsync(
        _ frame: UnsafeMutablePointer<TDCallFrame>
    ) -> UnsafeMutableRawPointer? {
        let slot = Int(frame.loadWord(at: TDFrame.slot))
        guard let recorder = findRecorder(in: frame) else {
            fatalError("[TestDoubles] Trampoline could not resolve recorder for witness call at slot \(slot).")
        }
        guard let method = recorder.runtimeMethod(for: slot) else {
            fatalError("[TestDoubles] No method descriptor registered for witness slot \(slot).")
        }
        let args = decodeArguments(for: method, from: frame)
        switch recorder.prepareAsyncDispatch(method: method, args: args) {
        case .placeholder:
            frame.storeWord(0, at: TDFrame.returnError)
            encodeRecordingPlaceholder(for: method, args: args, into: frame)
            return nil

        case .immediate(.success(let result)):
            frame.storeWord(0, at: TDFrame.returnError)
            encodeReturn(result, for: method, into: frame)
            return nil

        case .immediate(.failure(let error)):
            guard method.isThrowing else {
                fatalError("[TestDoubles] A nonthrowing async stub handler threw \(error).")
            }
            frame.zeroReturn()
            frame.storeWord(swiftErrorPointer(error), at: TDFrame.returnError)
            return nil

        case .suspending(let handler):
            let state = AsyncDispatchState(
                frame: frame.pointee,
                method: method,
                args: args,
                handler: handler
            )
            return Unmanaged.passRetained(state).toOpaque()
        }
    }

    static func dispatchAsync(_ rawState: UnsafeMutableRawPointer) async {
        let state = Unmanaged<AsyncDispatchState>.fromOpaque(rawState).takeUnretainedValue()
        await state.run()
    }

    static func finishAsync(
        _ rawState: UnsafeMutableRawPointer,
        into frame: UnsafeMutablePointer<TDCallFrame>
    ) {
        let state = Unmanaged<AsyncDispatchState>.fromOpaque(rawState).takeRetainedValue()
        frame.pointee = state.frame
    }

    private static func findRecorder(in frame: UnsafeMutablePointer<TDCallFrame>) -> StubRecorder? {
        let context = frame.loadWord(at: TDFrame.context)
        guard let key = UnsafeRawPointer(bitPattern: context) else { return nil }
        return MockRegistry.resolveOptional(key)
    }

    private static func decodeArguments(for method: MethodDescriptor, from frame: UnsafeMutablePointer<TDCallFrame>) -> [Any] {
        let returnABI = method.returnLayout
        let hasAsyncIndirectResult: Bool
        if method.isAsync, case .indirect = returnABI {
            hasAsyncIndirectResult = true
        } else {
            hasAsyncIndirectResult = false
        }
        var cursor = ArgumentCursor(gp: hasAsyncIndirectResult ? 1 : 0)
        var values: [Any] = []
        values.reserveCapacity(method.argumentTypes.count)

        for (type, abi) in zip(method.argumentTypes, method.argumentLayouts) {
            switch abi {
            case .void:
                values.append(())

            case .floatingPoint:
                let bits = frame.takeFPWord(&cursor)
                if type == Float.self {
                    var raw = UInt32(truncatingIfNeeded: bits)
                    values.append(boxValue(type: Float.self, source: &raw))
                } else {
                    var raw = bits
                    values.append(boxValue(type: type, source: &raw))
                }

            case .integer(let words):
                var storage = (UInt64(0), UInt64(0))
                withUnsafeMutableBytes(of: &storage) { bytes in
                    for word in 0..<words {
                        bytes.storeBytes(of: UInt64(frame.takeGPWord(&cursor)), toByteOffset: word * 8, as: UInt64.self)
                    }
                }
                values.append(withUnsafeMutablePointer(to: &storage) {
                    boxValue(type: type, source: UnsafeMutableRawPointer($0))
                })

            case .aggregate(let parts):
                values.append(decodeAggregateArgument(type: type, parts: parts, cursor: &cursor, from: frame))

            case .indirect:
                let address = frame.takeGPWord(&cursor)
                guard let source = UnsafeMutableRawPointer(bitPattern: address) else {
                    fatalError("[TestDoubles] Missing indirect argument storage for \(method.name).")
                }
                values.append(boxValue(type: type, source: source))
            }
        }

        return values
    }

    private static func decodeAggregateArgument(
        type: Any.Type,
        parts: [DirectValuePart],
        cursor: inout ArgumentCursor,
        from frame: UnsafeMutablePointer<TDCallFrame>
    ) -> Any {
        let metadata = reflect(type)
        let byteCount = max(metadata.vwt.size, 1)
        let alignment = max(metadata.vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        let temp = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
        temp.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        for part in parts {
            let value: UInt64
            switch part.register {
            case .gp:
                value = UInt64(frame.takeGPWord(&cursor))
            case .fp:
                value = frame.takeFPWord(&cursor)
            }
            storeAggregatePart(value, part: part, into: temp)
        }
        let boxed = boxValue(type: type, source: temp)
        temp.deallocate()
        return boxed
    }

    private static func encodeReturn(_ result: Any, for method: MethodDescriptor, into frame: UnsafeMutablePointer<TDCallFrame>) {
        let abi = method.returnLayout
        frame.zeroReturn()

        switch abi {
        case .void:
            return

        case .floatingPoint:
            let bits = copiedReturnBytes(result, expectedType: method.returnType, byteCount: 8)
            frame.storeWord(bits.0, at: TDFrame.returnFP)

        case .integer(let words):
            let bytes = copiedReturnBytes(result, expectedType: method.returnType, byteCount: words * 8)
            frame.storeWord(bytes.0, at: TDFrame.returnGP)
            if words > 1 {
                frame.storeWord(bytes.1, at: TDFrame.returnGP + 8)
            }

        case .aggregate(let parts):
            withCopiedReturn(result, expectedType: method.returnType) { source in
                encodeAggregateReturn(parts: parts, from: source, into: frame)
            }

        case .indirect:
            let destinationWord = frame.loadWord(at: TDFrame.indirectResult)
            guard let destination = UnsafeMutableRawPointer(bitPattern: destinationWord) else {
                fatalError("[TestDoubles] Missing indirect return buffer for \(method.name).")
            }
            copyReturn(result, expectedType: method.returnType, to: destination)
            #if arch(x86_64)
            if method.isAsync == false {
                frame.storeWord(destinationWord, at: TDFrame.returnGP)
            }
            #endif
        }
    }

    private static func encodeRecordingPlaceholder(
        for method: MethodDescriptor,
        args: [Any],
        into frame: UnsafeMutablePointer<TDCallFrame>
    ) {
        let abi = method.returnLayout
        frame.zeroReturn()

        switch abi {
        case .void:
            return
        case .floatingPoint:
            return
        case .integer(let words):
            if method.returnType == String.self {
                encodeReturn("", for: method, into: frame)
            } else if encodeInitializedPlaceholder(type: method.returnType, for: method, into: frame) {
                return
            } else if words > 1 {
                frame.storeWord(0, at: TDFrame.returnGP + 8)
            }
        case .aggregate(let parts):
            let returnType = method.returnType
            var visited: Set<UInt> = []
            guard canInitializePlaceholder(type: returnType, visited: &visited) else {
                fatalError("[TestDoubles] Stub cannot synthesize a recording placeholder for \(returnType). Use a hand-written test double for \(method.name).")
            }
            initializeAggregatePlaceholder(type: returnType, parts: parts, into: frame)
        case .indirect:
            let destinationWord = frame.loadWord(at: TDFrame.indirectResult)
            guard let destination = UnsafeMutableRawPointer(bitPattern: destinationWord) else {
                fatalError("[TestDoubles] Cannot record indirect-return requirement \(method.name) without return metadata.")
            }
            let returnType = method.returnType
            #if arch(x86_64)
            if method.isAsync == false {
                frame.storeWord(destinationWord, at: TDFrame.returnGP)
            }
            #endif
            if reflect(returnType) is ExistentialMetadata,
               let index = method.argumentTypes.firstIndex(where: { $0 == returnType }),
               args.indices.contains(index) {
                copyReturn(args[index], expectedType: returnType, to: destination)
                return
            }
            guard initializePlaceholder(type: returnType, at: destination) else {
                fatalError("[TestDoubles] Stub cannot synthesize a recording placeholder for \(returnType). Use a hand-written test double for \(method.name).")
            }
        }
    }

    private static func encodeInitializedPlaceholder(
        type: Any.Type,
        for method: MethodDescriptor,
        into frame: UnsafeMutablePointer<TDCallFrame>
    ) -> Bool {
        let metadata = reflect(type)
        let byteCount = max(metadata.vwt.size, 1)
        let alignment = max(metadata.vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
        guard initializePlaceholder(type: type, at: storage) else {
            storage.deallocate()
            return false
        }
        let value = boxValue(type: type, source: storage)
        metadata.vwt.destroy(storage)
        storage.deallocate()
        encodeReturn(value, for: method, into: frame)
        return true
    }

    private static func initializeAggregatePlaceholder(
        type: Any.Type,
        parts: [DirectValuePart],
        into frame: UnsafeMutablePointer<TDCallFrame>
    ) {
        let metadata = reflect(type)
        let byteCount = max(metadata.vwt.size, 16)
        let alignment = max(metadata.vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        let temp = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
        temp.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        var visited: Set<UInt> = []
        initializeKnownPlaceholder(type: type, at: temp, visited: &visited)
        encodeAggregateReturn(parts: parts, from: temp, into: frame)
        // The encoded return registers take ownership of the initialized value.
        temp.deallocate()
    }

    private static func encodeAggregateReturn(
        parts: [DirectValuePart],
        from source: UnsafeMutableRawPointer,
        into frame: UnsafeMutablePointer<TDCallFrame>
    ) {
        var gp = 0
        var fp = 0
        for part in parts {
            let value = loadAggregatePart(part, from: source)
            switch part.register {
            case .gp:
                guard gp < TDFrame.returnGPCount else {
                    fatalError("[TestDoubles] Direct aggregate return uses too many general-purpose registers.")
                }
                frame.storeWord(UInt(truncatingIfNeeded: value), at: TDFrame.returnGP + gp * 8)
                gp += 1
            case .fp:
                guard fp < TDFrame.returnFPCount else {
                    fatalError("[TestDoubles] Direct aggregate return uses too many floating-point registers.")
                }
                frame.storeWord(UInt(truncatingIfNeeded: value), at: TDFrame.returnFP + fp * 8)
                fp += 1
            }
        }
    }

    private static func storeAggregatePart(
        _ value: UInt64,
        part: DirectValuePart,
        into destination: UnsafeMutableRawPointer
    ) {
        let field = destination + part.offset
        switch part.byteCount {
        case 1:
            field.storeBytes(of: UInt8(truncatingIfNeeded: value), as: UInt8.self)
        case 2:
            field.storeBytes(of: UInt16(truncatingIfNeeded: value), as: UInt16.self)
        case 4:
            field.storeBytes(of: UInt32(truncatingIfNeeded: value), as: UInt32.self)
        case 8:
            field.storeBytes(of: value, as: UInt64.self)
        default:
            for index in 0..<min(part.byteCount, MemoryLayout<UInt64>.size) {
                (field + index).storeBytes(
                    of: UInt8(truncatingIfNeeded: value >> UInt64(index * 8)),
                    as: UInt8.self
                )
            }
        }
    }

    private static func loadAggregatePart(_ part: DirectValuePart, from source: UnsafeMutableRawPointer) -> UInt64 {
        let field = source + part.offset
        switch part.byteCount {
        case 1:
            return UInt64(field.loadUnaligned(as: UInt8.self))
        case 2:
            return UInt64(field.loadUnaligned(as: UInt16.self))
        case 4:
            return UInt64(field.loadUnaligned(as: UInt32.self))
        case 8:
            return field.loadUnaligned(as: UInt64.self)
        default:
            var value = UInt64(0)
            let count = min(part.byteCount, MemoryLayout<UInt64>.size)
            for index in 0..<count {
                value |= UInt64((field + index).load(as: UInt8.self)) << UInt64(index * 8)
            }
            return value
        }
    }

    private static func initializePlaceholder(type: Any.Type, at destination: UnsafeMutableRawPointer) -> Bool {
        var visited: Set<UInt> = []
        guard canInitializePlaceholder(type: type, visited: &visited) else {
            return false
        }
        destination.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: max(reflect(type).vwt.size, 1)
        )
        visited.removeAll()
        initializeKnownPlaceholder(type: type, at: destination, visited: &visited)
        return true
    }

    private static func canInitializePlaceholder(type: Any.Type, visited: inout Set<UInt>) -> Bool {
        if isKnownPlaceholderType(type) {
            return true
        }
        let metadata = reflect(type)
        if let enumMetadata = metadata as? EnumMetadata {
            return enumMetadata.descriptor.numEmptyCases > 0
        }
        if let tupleMetadata = metadata as? TupleMetadata {
            return tupleMetadata.elements.allSatisfy {
                canInitializePlaceholder(type: $0.type, visited: &visited)
            }
        }
        if metadata is MetatypeMetadata || metadata is ExistentialMetatypeMetadata {
            return true
        }
        guard let structMetadata = metadata as? StructMetadata else {
            return false
        }
        let key = UInt(bitPattern: structMetadata.ptr)
        guard visited.insert(key).inserted else {
            return false
        }
        defer { visited.remove(key) }

        let fields = structMetadata.descriptor.fields.records
        let offsets = structMetadata.fieldOffsets
        guard fields.count == offsets.count else {
            return false
        }
        for field in fields {
            guard field.hasMangledTypeName,
                  let fieldType = structMetadata.type(of: field.mangledTypeName),
                  canInitializePlaceholder(type: fieldType, visited: &visited) else {
                return false
            }
        }
        return true
    }

    private static func initializeKnownPlaceholder(
        type: Any.Type,
        at destination: UnsafeMutableRawPointer,
        visited: inout Set<UInt>
    ) {
        switch type {
        case is Int.Type:
            initializeValue(0 as Int, at: destination)
        case is Int8.Type:
            initializeValue(0 as Int8, at: destination)
        case is Int16.Type:
            initializeValue(0 as Int16, at: destination)
        case is Int32.Type:
            initializeValue(0 as Int32, at: destination)
        case is Int64.Type:
            initializeValue(0 as Int64, at: destination)
        case is UInt.Type:
            initializeValue(0 as UInt, at: destination)
        case is UInt8.Type:
            initializeValue(0 as UInt8, at: destination)
        case is UInt16.Type:
            initializeValue(0 as UInt16, at: destination)
        case is UInt32.Type:
            initializeValue(0 as UInt32, at: destination)
        case is UInt64.Type:
            initializeValue(0 as UInt64, at: destination)
        case is Bool.Type:
            initializeValue(false, at: destination)
        case is Float.Type:
            initializeValue(0 as Float, at: destination)
        case is Double.Type:
            initializeValue(0 as Double, at: destination)
        case is String.Type:
            initializeValue("", at: destination)
        case is [String].Type:
            initializeValue([String](), at: destination)
        case is [Int].Type:
            initializeValue([Int](), at: destination)
        case is [Double].Type:
            initializeValue([Double](), at: destination)
        default:
            let metadata = reflect(type)
            if let enumMetadata = metadata as? EnumMetadata {
                enumMetadata.enumVwt.destructiveInjectEnumTag(
                    for: destination,
                    tag: UInt32(enumMetadata.descriptor.numPayloadCases)
                )
                return
            }
            if let tupleMetadata = metadata as? TupleMetadata {
                for element in tupleMetadata.elements {
                    initializeKnownPlaceholder(
                        type: element.type,
                        at: destination + element.offset,
                        visited: &visited
                    )
                }
                return
            }
            if let metatypeMetadata = metadata as? MetatypeMetadata {
                destination.storeBytes(
                    of: UInt(bitPattern: unsafeBitCast(
                        metatypeMetadata.instanceType,
                        to: UnsafeRawPointer.self
                    )),
                    as: UInt.self
                )
                return
            }
            if let metatypeMetadata = metadata as? ExistentialMetatypeMetadata {
                destination.storeBytes(
                    of: UInt(bitPattern: unsafeBitCast(
                        metatypeMetadata.instanceType,
                        to: UnsafeRawPointer.self
                    )),
                    as: UInt.self
                )
                return
            }
            guard let structMetadata = metadata as? StructMetadata else {
                preconditionFailure("[TestDoubles] Missing placeholder preflight for \(type).")
            }
            let key = UInt(bitPattern: structMetadata.ptr)
            precondition(visited.insert(key).inserted, "[TestDoubles] Recursive placeholder type \(type).")
            defer { visited.remove(key) }

            let fields = structMetadata.descriptor.fields.records
            let offsets = structMetadata.fieldOffsets
            for (field, offset) in zip(fields, offsets) {
                guard let fieldType = structMetadata.type(of: field.mangledTypeName) else {
                    preconditionFailure("[TestDoubles] Missing field metadata for placeholder type \(type).")
                }
                initializeKnownPlaceholder(type: fieldType, at: destination + offset, visited: &visited)
            }
        }
    }

    private static func isKnownPlaceholderType(_ type: Any.Type) -> Bool {
        type == Int.self ||
        type == Int8.self ||
        type == Int16.self ||
        type == Int32.self ||
        type == Int64.self ||
        type == UInt.self ||
        type == UInt8.self ||
        type == UInt16.self ||
        type == UInt32.self ||
        type == UInt64.self ||
        type == Bool.self ||
        type == Float.self ||
        type == Double.self ||
        type == String.self ||
        type == [String].self ||
        type == [Int].self ||
        type == [Double].self
    }

    private static func initializeValue<T>(_ value: T, at destination: UnsafeMutableRawPointer) {
        var value = value
        let metadata = reflect(T.self)
        withUnsafeMutablePointer(to: &value) {
            metadata.vwt.initializeWithCopy(destination, UnsafeMutableRawPointer($0))
        }
    }

    private static func copiedReturnBytes(_ result: Any, expectedType: Any.Type?, byteCount: Int) -> (UInt, UInt) {
        var first = UInt(0)
        var second = UInt(0)
        withCopiedReturn(result, expectedType: expectedType) { source in
            if byteCount > 0 {
                first = source.loadUnaligned(as: UInt.self)
            }
            if byteCount > 8 {
                second = (source + 8).loadUnaligned(as: UInt.self)
            }
        }
        return (first, second)
    }

    private static func copyReturn(_ result: Any, expectedType: Any.Type?, to destination: UnsafeMutableRawPointer) {
        var container = Echo.container(for: result)
        let actual = container.metadata
        let metadata = expectedType.map(reflect) ?? actual
        if let expectedType, actual.type != expectedType {
            if metadata is ExistentialMetadata {
                func copyOpenedExistential<T>(_ type: T.Type) {
                    guard let value = result as? T else {
                        preconditionFailure(
                            "[TestDoubles] \(actual.type) does not satisfy existential return type \(expectedType)."
                        )
                    }
                    withUnsafePointer(to: value) {
                        metadata.vwt.initializeWithCopy(
                            destination,
                            UnsafeMutableRawPointer(mutating: $0)
                        )
                    }
                }
                _openExistential(expectedType, do: copyOpenedExistential)
                return
            }
            preconditionFailure("[TestDoubles] Type mismatch: expected \(expectedType), got \(actual.type).")
        }
        metadata.vwt.initializeWithCopy(destination, UnsafeMutableRawPointer(mutating: container.projectValue()))
    }

    private static func withCopiedReturn(_ result: Any, expectedType: Any.Type?, _ body: (UnsafeMutableRawPointer) -> Void) {
        var container = Echo.container(for: result)
        let actual = container.metadata
        let metadata = expectedType.map(reflect) ?? actual
        if let expectedType, actual.type != expectedType {
            preconditionFailure("[TestDoubles] Type mismatch: expected \(expectedType), got \(actual.type).")
        }

        let byteCount = max(metadata.vwt.size, 16)
        let alignment = max(metadata.vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        let temp = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
        temp.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        metadata.vwt.initializeWithCopy(temp, UnsafeMutableRawPointer(mutating: container.projectValue()))
        body(temp)
        // The caller receives the copied value through ABI return storage.
        temp.deallocate()
    }
}

private struct ArgumentCursor {
    var gp = 0
    var fp = 0
    var stack = 0
}

private enum TDFrame {
    static let slot = Int(TD_FRAME_SLOT_OFFSET)
    static let context = Int(TD_FRAME_CONTEXT_OFFSET)
    static let gp = Int(TD_FRAME_GP_OFFSET)
    static let fp = Int(TD_FRAME_FP_OFFSET)
    static let stackPointer = Int(TD_FRAME_STACK_POINTER_OFFSET)
    static let indirectResult = Int(TD_FRAME_INDIRECT_RESULT_OFFSET)
    static let swiftError = Int(TD_FRAME_SWIFT_ERROR_OFFSET)
    static let returnGP = Int(TD_FRAME_RETURN_GP_OFFSET)
    static let returnFP = Int(TD_FRAME_RETURN_FP_OFFSET)
    static let returnError = Int(TD_FRAME_RETURN_ERROR_OFFSET)
    static let returnGPCount = 4
    static let returnFPCount = 4
    #if arch(x86_64)
    static let registerGPArgumentLimit = 6
    #else
    static let registerGPArgumentLimit = 8
    #endif
    static let registerFPArgumentLimit = 8
}

private extension UnsafeMutablePointer where Pointee == TDCallFrame {
    var raw: UnsafeMutableRawPointer { UnsafeMutableRawPointer(self) }

    func loadWord(at offset: Int) -> UInt {
        raw.loadUnaligned(fromByteOffset: offset, as: UInt.self)
    }

    func storeWord(_ value: UInt, at offset: Int) {
        raw.storeBytes(of: value, toByteOffset: offset, as: UInt.self)
    }

    func gpWord(_ index: Int) -> UInt {
        loadWord(at: TDFrame.gp + index * 8)
    }

    func fpLowWord(_ index: Int) -> UInt64 {
        raw.loadUnaligned(fromByteOffset: TDFrame.fp + index * 16, as: UInt64.self)
    }

    func stackWord(_ index: Int) -> UInt {
        let address = loadWord(at: TDFrame.stackPointer)
        guard let stack = UnsafeRawPointer(bitPattern: address) else {
            preconditionFailure("[TestDoubles] Trampoline captured an invalid stack pointer.")
        }
        return stack.loadUnaligned(fromByteOffset: index * 8, as: UInt.self)
    }

    func takeGPWord(_ cursor: inout ArgumentCursor) -> UInt {
        if cursor.gp < TDFrame.registerGPArgumentLimit {
            defer { cursor.gp += 1 }
            return gpWord(cursor.gp)
        }
        defer { cursor.stack += 1 }
        return stackWord(cursor.stack)
    }

    func takeFPWord(_ cursor: inout ArgumentCursor) -> UInt64 {
        if cursor.fp < TDFrame.registerFPArgumentLimit {
            defer { cursor.fp += 1 }
            return fpLowWord(cursor.fp)
        }
        defer { cursor.stack += 1 }
        return UInt64(stackWord(cursor.stack))
    }

    func zeroReturn() {
        for index in 0..<TDFrame.returnGPCount {
            storeWord(0, at: TDFrame.returnGP + index * 8)
        }
        for index in 0..<TDFrame.returnFPCount {
            storeWord(0, at: TDFrame.returnFP + index * 8)
        }
    }
}

private func boxValue<T>(type: T.Type, source: UnsafeMutableRawPointer) -> Any {
    boxValue(type: type as Any.Type, source: source)
}

private func boxValue(type: Any.Type, source: UnsafeMutableRawPointer) -> Any {
    func boxOpenedValue<T>(_ type: T.Type) -> Any {
        source.assumingMemoryBound(to: T.self).pointee
    }
    return _openExistential(type, do: boxOpenedValue)
}

private func swiftErrorPointer(_ error: any Error) -> UInt {
    var container = Echo.container(for: error)
    let metadata = container.metadata
    guard let errorProtocol = (reflect((any Error).self) as? ExistentialMetadata)?.protocols.first,
          let witness = swift_conformsToProtocol(metadata: metadata, protocol: errorProtocol) else {
        fatalError("[TestDoubles] Cannot find Error witness table for thrown value of type \(metadata.type).")
    }
    let allocated = td_swift_alloc_error(metadata.ptr, witness.ptr, nil, false)
    metadata.vwt.initializeWithCopy(
        allocated.value,
        UnsafeMutableRawPointer(mutating: container.projectValue())
    )
    return UInt(bitPattern: allocated.error)
}
