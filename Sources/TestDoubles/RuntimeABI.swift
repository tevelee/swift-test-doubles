// Swift ABI classification used by the runtime trampoline.
import Echo
import Foundation

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

func abiClass(for type: Any.Type?, fallbackName: String, isReturn: Bool = false) -> ABIClass {
    if let fallback = fallbackABIClass(for: fallbackName, isReturn: isReturn) {
        return fallback
    }

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
    if directArgumentParts(for: type) != nil {
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

private func fallbackABIClass(for typeName: String, isReturn: Bool) -> ABIClass? {
    if isReturn, ["V", "Void", "Swift.Void", "()"].contains(typeName) {
        return .void
    }

    switch typeName {
    case "INDIRECT":
        return .indirect
    case "FX", "Double", "Swift.Double", "Float", "Swift.Float":
        return .floatingPoint
    case "W2", "String", "Swift.String":
        return .integer(words: 2)
    case "W1":
        return .integer(words: 1)
    default:
        return nil
    }
}

private func isFloatingPoint(_ type: Any.Type) -> Bool {
    type == Float.self || type == Double.self
}

func directArgumentParts(for type: Any.Type) -> [DirectValuePart]? {
    let metadata = reflect(type)
    guard metadata.vwt.size <= 16,
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

    if let tupleMetadata = metadata as? TupleMetadata {
        for element in tupleMetadata.elements {
            guard appendDirectValueParts(
                for: element.type,
                baseOffset: baseOffset + element.offset,
                parts: &parts,
                visited: &visited
            ) else {
                return false
            }
        }
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
