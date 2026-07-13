#if RUNTIME_STUB
import CTestDoublesTrampoline
import Echo
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct RuntimeMethodDescriptor {
    let name: String
    let signature: MethodSignature
    let qualifiedArgs: [String]
    let qualifiedRet: String
    let isThrowing: Bool
    let isAsync: Bool
    let argumentTypes: [Any.Type?]
    let returnType: Any.Type?

    init(_ descriptor: MethodDescriptor) {
        self.name = descriptor.name
        self.signature = descriptor.signature
        self.qualifiedArgs = descriptor.qualifiedArgs
        self.qualifiedRet = descriptor.qualifiedRet
        self.isThrowing = descriptor.isThrowing
        self.isAsync = descriptor.isAsync
        self.argumentTypes = descriptor.qualifiedArgs.map(resolveRuntimeType)
        self.returnType = resolveRuntimeType(descriptor.qualifiedRet)
    }
}

@_cdecl("td_swift_trampoline_handler")
func td_swift_trampoline_handler(_ rawFrame: UnsafeMutablePointer<TDCallFrame>?) {
    guard let rawFrame else { return }
    RuntimeTrampolineHandler.handle(rawFrame)
}

private enum RuntimeTrampolineHandler {
    static func handle(_ frame: UnsafeMutablePointer<TDCallFrame>) {
        let slot = Int(frame.loadWord(at: TDFrame.slot))
        guard let recorder = findRecorder(in: frame) else {
            fatalError("[TestDoubles] Trampoline could not resolve recorder for witness call at slot \(slot).")
        }
        guard let method = recorder.runtimeMethod(for: slot) else {
            fatalError("[TestDoubles] No method descriptor registered for witness slot \(slot).")
        }
        guard !method.isAsync else {
            fatalError("[TestDoubles] RuntimeStub trampoline does not support async witness entries yet. Use CompiledStub for async requirements.")
        }

        let args = decodeArguments(for: method, from: frame)
        let result: Any

        if method.isThrowing, let throwingResult = recorder.dispatchThrowing(method: slot, args: args) {
            switch throwingResult {
            case .success(let value):
                result = value
                frame.storeWord(0, at: TDFrame.returnError)
            case .failure(let error):
                frame.storeWord(swiftErrorPointer(error), at: TDFrame.returnError)
                return
            }
        } else {
            result = recorder.dispatch(method: slot, args: args)
            if method.isThrowing {
                frame.storeWord(0, at: TDFrame.returnError)
            } else {
                frame.storeWord(frame.loadWord(at: TDFrame.swiftError), at: TDFrame.returnError)
            }
        }

        if recorder.mode == .normal {
            encodeReturn(result, for: method, into: frame)
        } else {
            encodeRecordingPlaceholder(for: method, into: frame)
        }
    }

    private static func findRecorder(in frame: UnsafeMutablePointer<TDCallFrame>) -> StubRecorder? {
        let context = frame.loadWord(at: TDFrame.context)
        guard let key = UnsafeRawPointer(bitPattern: context) else { return nil }
        return MockRegistry.resolveOptional(key)
    }

    private static func decodeArguments(for method: RuntimeMethodDescriptor, from frame: UnsafeMutablePointer<TDCallFrame>) -> [Any] {
        var cursor = ArgumentCursor()
        var values: [Any] = []
        values.reserveCapacity(method.signature.args.count)

        for index in method.signature.args.indices {
            let fallbackName = method.qualifiedArgs.indices.contains(index) ? method.qualifiedArgs[index] : method.signature.args[index]
            let type = method.argumentTypes.indices.contains(index) ? method.argumentTypes[index] : nil
            let abi = abiClass(for: type, fallbackName: fallbackName)

            switch abi {
            case .void:
                values.append(())

            case .floatingPoint:
                let bits = frame.takeFPWord(&cursor)
                if type == Float.self || fallbackName == "Float" || fallbackName == "Swift.Float" {
                    var raw = UInt32(truncatingIfNeeded: bits)
                    values.append(boxValue(type: Float.self, source: &raw))
                } else {
                    var raw = bits
                    values.append(boxValue(type: type ?? Double.self, source: &raw))
                }

            case .integer(let words):
                var storage = (UInt64(0), UInt64(0))
                withUnsafeMutableBytes(of: &storage) { bytes in
                    for word in 0..<words {
                        bytes.storeBytes(of: UInt64(frame.takeGPWord(&cursor)), toByteOffset: word * 8, as: UInt64.self)
                    }
                }
                if let type {
                    values.append(withUnsafeMutablePointer(to: &storage) {
                        boxValue(type: type, source: UnsafeMutableRawPointer($0))
                    })
                } else {
                    values.append(fallbackValue(from: storage, words: words, typeName: fallbackName))
                }

            case .aggregate:
                guard let type, let parts = directArgumentParts(for: type) else {
                    fatalError("[TestDoubles] Missing direct aggregate argument metadata for \(method.name).")
                }
                values.append(decodeAggregateArgument(type: type, parts: parts, cursor: &cursor, from: frame))

            case .indirect:
                let address = frame.takeGPWord(&cursor)
                guard let type, let source = UnsafeMutableRawPointer(bitPattern: address) else {
                    values.append(UnsafeRawPointer(bitPattern: address) as Any)
                    continue
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

    private static func encodeReturn(_ result: Any, for method: RuntimeMethodDescriptor, into frame: UnsafeMutablePointer<TDCallFrame>) {
        let abi = abiClass(for: method.returnType, fallbackName: method.qualifiedRet, isReturn: true)
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

        case .aggregate:
            guard let returnType = method.returnType,
                  let parts = directReturnParts(for: returnType) else {
                fatalError("[TestDoubles] Missing direct aggregate return metadata for \(method.name).")
            }
            withCopiedReturn(result, expectedType: method.returnType) { source in
                encodeAggregateReturn(parts: parts, from: source, into: frame)
            }

        case .indirect:
            let destinationWord = frame.loadWord(at: TDFrame.indirectResult)
            guard let destination = UnsafeMutableRawPointer(bitPattern: destinationWord) else {
                fatalError("[TestDoubles] Missing indirect return buffer for \(method.name).")
            }
            copyReturn(result, expectedType: method.returnType, to: destination)
        }
    }

    private static func encodeRecordingPlaceholder(for method: RuntimeMethodDescriptor, into frame: UnsafeMutablePointer<TDCallFrame>) {
        let abi = abiClass(for: method.returnType, fallbackName: method.qualifiedRet, isReturn: true)
        frame.zeroReturn()

        switch abi {
        case .void:
            return
        case .floatingPoint:
            return
        case .integer(let words):
            if method.returnType == String.self || method.qualifiedRet == "String" || method.qualifiedRet == "Swift.String" {
                encodeReturn("", for: method, into: frame)
            } else if words > 1 {
                frame.storeWord(0, at: TDFrame.returnGP + 8)
            }
        case .aggregate:
            guard let returnType = method.returnType,
                  let parts = directReturnParts(for: returnType) else {
                fatalError("[TestDoubles] Cannot record direct aggregate return for \(method.name) without return metadata.")
            }
            var visited: Set<UInt> = []
            guard canInitializePlaceholder(type: returnType, visited: &visited) else {
                fatalError("[TestDoubles] RuntimeStub cannot synthesize a recording placeholder for \(returnType). Use CompiledStub or ManualStub for \(method.name).")
            }
            initializeAggregatePlaceholder(type: returnType, parts: parts, into: frame)
        case .indirect:
            let destinationWord = frame.loadWord(at: TDFrame.indirectResult)
            guard let destination = UnsafeMutableRawPointer(bitPattern: destinationWord),
                  let returnType = method.returnType else {
                fatalError("[TestDoubles] Cannot record indirect-return requirement \(method.name) without return metadata.")
            }
            guard initializePlaceholder(type: returnType, at: destination) else {
                fatalError("[TestDoubles] RuntimeStub cannot synthesize a recording placeholder for \(returnType). Use CompiledStub or ManualStub for \(method.name).")
            }
        }
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
        visited.removeAll()
        initializeKnownPlaceholder(type: type, at: destination, visited: &visited)
        return true
    }

    private static func canInitializePlaceholder(type: Any.Type, visited: inout Set<UInt>) -> Bool {
        if isKnownPlaceholderType(type) {
            return true
        }
        guard let metadata = reflectStruct(type) else {
            return false
        }
        let key = UInt(bitPattern: metadata.ptr)
        guard visited.insert(key).inserted else {
            return false
        }
        defer { visited.remove(key) }

        let fields = metadata.descriptor.fields.records
        let offsets = metadata.fieldOffsets
        guard fields.count == offsets.count else {
            return false
        }
        for field in fields {
            guard field.hasMangledTypeName,
                  let fieldType = metadata.type(of: field.mangledTypeName),
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
            guard let metadata = reflectStruct(type) else {
                preconditionFailure("[TestDoubles] Missing placeholder preflight for \(type).")
            }
            let key = UInt(bitPattern: metadata.ptr)
            precondition(visited.insert(key).inserted, "[TestDoubles] Recursive placeholder type \(type).")
            defer { visited.remove(key) }

            let fields = metadata.descriptor.fields.records
            let offsets = metadata.fieldOffsets
            for (field, offset) in zip(fields, offsets) {
                guard let fieldType = metadata.type(of: field.mangledTypeName) else {
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

private func fallbackValue(from storage: (UInt64, UInt64), words: Int, typeName: String) -> Any {
    var storage = storage
    switch typeName {
    case "Bool", "Swift.Bool":
        return storage.0 != 0
    case "Double", "Swift.Double":
        return Double(bitPattern: storage.0)
    case "Float", "Swift.Float":
        return Float(bitPattern: UInt32(truncatingIfNeeded: storage.0))
    case "String", "Swift.String":
        return withUnsafeMutablePointer(to: &storage) {
            boxValue(type: String.self, source: UnsafeMutableRawPointer($0))
        }
    default:
        if words == 1 {
            return Int(bitPattern: UInt(storage.0))
        }
        return storage
    }
}

private func boxValue<T>(type: T.Type, source: UnsafeMutableRawPointer) -> Any {
    boxValue(type: type as Any.Type, source: source)
}

private func boxValue(type: Any.Type, source: UnsafeMutableRawPointer) -> Any {
    let metadata = reflect(type)
    var container = AnyExistentialContainer(type: type)
    let destination = UnsafeMutableRawPointer(mutating: metadata.allocateBoxForExistential(in: &container))
    metadata.vwt.initializeWithCopy(destination, source)
    return unsafeBitCast(container, to: Any.self)
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

private func resolveRuntimeType(_ name: String) -> Any.Type? {
    switch name {
    case "V", "Void", "Swift.Void", "()": return Void.self
    case "W1", "INDIRECT": return nil
    case "Int", "Swift.Int": return Int.self
    case "Bool", "Swift.Bool": return Bool.self
    case "W2", "String", "Swift.String": return String.self
    case "FX", "Double", "Swift.Double": return Double.self
    case "Float", "Swift.Float": return Float.self
    case "[String]", "[Swift.String]": return [String].self
    case "[Int]", "[Swift.Int]": return [Int].self
    case "[Double]", "[Swift.Double]": return [Double].self
    default:
        if let type = _typeByName(name) {
            return type
        }
        if !name.contains("."), let type = _typeByName("Swift.\(name)") {
            return type
        }
        if let type = swiftTypeByNominalName(name) {
            return type
        }
        return swiftTypeByMangledName(name)
    }
}

private func swiftTypeByNominalName(_ name: String) -> Any.Type? {
    let parts = name.split(separator: ".").map(String.init)
    guard parts.count == 2 else { return nil }
    let module = parts[0]
    let typeName = parts[1]
    let prefix = "\(module.utf8.count)\(module)\(typeName.utf8.count)\(typeName)"
    for suffix in ["V", "O", "C"] {
        if let type = swiftTypeByMangledName(prefix + suffix) {
            return type
        }
    }
    return nil
}

private func swiftTypeByMangledName(_ name: String) -> Any.Type? {
    guard let swiftGetTypeByMangledNameInContext else {
        return nil
    }
    return name.utf8CString.withUnsafeBufferPointer { buffer -> Any.Type? in
        guard let base = buffer.baseAddress else { return nil }
        guard let metadata = swiftGetTypeByMangledNameInContext(
            UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
            UInt(name.utf8.count),
            nil,
            nil
        ) else {
            return nil
        }
        return unsafeBitCast(metadata, to: Any.Type.self)
    }
}

private typealias SwiftGetTypeByMangledNameInContext = @convention(c) (
    UnsafePointer<UInt8>,
    UInt,
    UnsafeRawPointer?,
    UnsafeRawPointer?
) -> UnsafeRawPointer?

private let swiftGetTypeByMangledNameInContext: SwiftGetTypeByMangledNameInContext? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "swift_getTypeByMangledNameInContext") else {
        return nil
    }
    return unsafeBitCast(symbol, to: SwiftGetTypeByMangledNameInContext.self)
}()

#endif
