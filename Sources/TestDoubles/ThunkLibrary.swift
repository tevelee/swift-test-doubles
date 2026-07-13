// Fixed trampoline backend for witness table patching.
#if RUNTIME_STUB
import CTestDoublesTrampoline
import Echo
import Foundation

/// Describes a method signature for runtime marshalling.
public struct MethodSignature: Hashable, Sendable, CustomStringConvertible {
    public let args: [String]
    public let ret: String

    public init(args: [String], ret: String) {
        self.args = args
        self.ret = ret
    }

    public static func getter(_ type: String) -> MethodSignature { .init(args: [], ret: type) }
    public static func method(_ args: [String], returning ret: String) -> MethodSignature { .init(args: args, ret: ret) }

    public var description: String {
        "(\(args.joined(separator: ", "))) -> \(ret)"
    }

    var abiSignature: MethodSignature {
        MethodSignature(args: args.map(argABI), ret: retABI(ret))
    }
}

enum ABIClass: Sendable {
    case void
    case integer(words: Int)
    case floatingPoint
    case aggregate
    case indirect
}

enum DirectValueRegister: Equatable, Sendable {
    case gp
    case fp
}

struct DirectValuePart: Sendable {
    let register: DirectValueRegister
    let offset: Int
    let byteCount: Int
}

func argABI(_ typeName: String) -> String {
    switch typeName {
    case "W1", "W2", "FX", "INDIRECT": return typeName
    case "String", "Swift.String": return "W2"
    case "Double", "Swift.Double", "Float", "Swift.Float": return "FX"
    default: return "W1"
    }
}

func retABI(_ typeName: String) -> String {
    switch typeName {
    case "W1", "W2", "FX", "V", "INDIRECT": return typeName
    case "Void", "Swift.Void", "()": return "V"
    case "String", "Swift.String": return "W2"
    case "Double", "Swift.Double", "Float", "Swift.Float": return "FX"
    default: return "W1"
    }
}

func abiClass(for type: Any.Type?, fallbackName: String, isReturn: Bool = false) -> ABIClass {
    let fallback = isReturn ? retABI(fallbackName) : argABI(fallbackName)
    if fallback == "V" { return .void }
    if fallback == "INDIRECT" { return .indirect }
    if fallback == "FX" { return .floatingPoint }
    if fallback == "W2" { return .integer(words: 2) }

    guard let type else {
        return .integer(words: 1)
    }

    let metadata = reflect(type)
    let size = metadata.vwt.size
    if size == 0 {
        return .void
    }
    if isFloatingPoint(type) {
        return .floatingPoint
    }
    if !isReturn, directArgumentParts(for: type) != nil {
        return .aggregate
    }
    if size > 16 {
        if isReturn, directReturnParts(for: type) != nil {
            return .aggregate
        }
        return .indirect
    }
    return .integer(words: size > 8 ? 2 : 1)
}

private func isFloatingPoint(_ type: Any.Type) -> Bool {
    type == Float.self || type == Double.self
}

func directArgumentParts(for type: Any.Type) -> [DirectValuePart]? {
    let metadata = reflect(type)
    guard metadata.vwt.size <= 16,
          reflectStruct(type) != nil,
          let parts = directReturnParts(for: type),
          parts.contains(where: { $0.register == .fp }) else {
        return nil
    }
    return parts
}

func directReturnParts(for type: Any.Type) -> [DirectValuePart]? {
    var visited: Set<UInt> = []
    var parts: [DirectValuePart] = []
    guard appendDirectValueParts(for: type, baseOffset: 0, parts: &parts, visited: &visited),
          parts.isEmpty == false,
          parts.count <= 4,
          parts.filter({ $0.register == .gp }).count <= 4,
          parts.filter({ $0.register == .fp }).count <= 4 else {
        return nil
    }
    return parts
}

private func appendDirectValueParts(
    for type: Any.Type,
    baseOffset: Int,
    parts: inout [DirectValuePart],
    visited: inout Set<UInt>
) -> Bool {
    let metadata = reflect(type)
    let size = metadata.vwt.size
    if size == 0 {
        return true
    }

    switch type {
    case is Float.Type:
        parts.append(DirectValuePart(register: .fp, offset: baseOffset, byteCount: 4))
        return true
    case is Double.Type:
        parts.append(DirectValuePart(register: .fp, offset: baseOffset, byteCount: 8))
        return true
    case is String.Type:
        parts.append(DirectValuePart(register: .gp, offset: baseOffset, byteCount: 8))
        parts.append(DirectValuePart(register: .gp, offset: baseOffset + 8, byteCount: 8))
        return true
    default:
        break
    }

    if isIntegerLike(type), size <= 8 {
        parts.append(DirectValuePart(register: .gp, offset: baseOffset, byteCount: size))
        return true
    }

    if metadata.kind == .class || metadata.kind == .foreignClass {
        parts.append(DirectValuePart(register: .gp, offset: baseOffset, byteCount: MemoryLayout<UInt>.size))
        return true
    }

    guard let structMetadata = reflectStruct(type) else {
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

    for (field, offset) in zip(fields, offsets) {
        guard field.hasMangledTypeName,
              let fieldType = structMetadata.type(of: field.mangledTypeName),
              appendDirectValueParts(
                for: fieldType,
                baseOffset: baseOffset + offset,
                parts: &parts,
                visited: &visited
              ) else {
            return false
        }
    }
    return true
}

private func isIntegerLike(_ type: Any.Type) -> Bool {
    type == Bool.self ||
    type == Int.self ||
    type == Int8.self ||
    type == Int16.self ||
    type == Int32.self ||
    type == Int64.self ||
    type == UInt.self ||
    type == UInt8.self ||
    type == UInt16.self ||
    type == UInt32.self ||
    type == UInt64.self
}

public enum ThunkLibrary {
    /// Creates a per-slot branch veneer over the single architecture trampoline.
    public static func thunk(for signature: MethodSignature, slot: Int, context: UnsafeRawPointer) -> UnsafeRawPointer? {
        guard let ptr = td_make_witness_trampoline(UInt(slot), UInt(bitPattern: context)) else {
            return nil
        }
        _ = signature
        return UnsafeRawPointer(ptr)
    }

    static func destroyThunk(_ pointer: UnsafeRawPointer) {
        td_free_witness_trampoline(UnsafeMutableRawPointer(mutating: pointer))
    }
}
#endif
