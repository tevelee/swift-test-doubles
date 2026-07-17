// Swift ABI classification used by the runtime trampoline.
import Echo
import Foundation

enum ABIClass: Sendable {
    case void
    case integer(words: Int)
    case floatingPoint
    case aggregate(parts: [DirectValuePart])
    case indirect
}

enum RuntimeArchitecture: Equatable, Sendable {
    case arm64
    case x86_64

    static var current: Self {
        #if arch(x86_64)
            .x86_64
        #else
            .arm64
        #endif
    }
}

enum DirectValueRegister: Equatable, Sendable {
    case gp
    case fp
}

struct DirectValuePart: Sendable {
    let register: DirectValueRegister
    let offset: Int
    let byteCount: Int

    /// Loads this part's bytes from in-memory value storage into a register word.
    func load(from source: UnsafeRawPointer) -> UInt64 {
        let field = source + offset
        switch byteCount {
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
                for index in 0 ..< min(byteCount, MemoryLayout<UInt64>.size) {
                    value |=
                        UInt64((field + index).load(as: UInt8.self))
                        << UInt64(index * 8)
                }
                return value
        }
    }

    /// Stores a register word into this part's bytes of in-memory value storage.
    func store(_ value: UInt64, into destination: UnsafeMutableRawPointer) {
        let field = destination + offset
        switch byteCount {
            case 1:
                field.storeBytes(
                    of: UInt8(truncatingIfNeeded: value),
                    as: UInt8.self
                )
            case 2:
                field.storeBytes(
                    of: UInt16(truncatingIfNeeded: value),
                    as: UInt16.self
                )
            case 4:
                field.storeBytes(
                    of: UInt32(truncatingIfNeeded: value),
                    as: UInt32.self
                )
            case 8:
                field.storeBytes(of: value, as: UInt64.self)
            default:
                for index in 0 ..< min(byteCount, MemoryLayout<UInt64>.size) {
                    (field + index).storeBytes(
                        of: UInt8(truncatingIfNeeded: value >> UInt64(index * 8)),
                        as: UInt8.self
                    )
                }
        }
    }
}

extension Metadata {
    /// The byte count of temporary storage for one value of this type, padded
    /// to `minimum` bytes so register-word codecs may address whole words.
    func valueBufferByteCount(minimum: Int = 1) -> Int {
        max(vwt.size, minimum)
    }

    /// Allocates uninitialized temporary storage for one value of this type,
    /// word-aligned so register-word codecs may address whole words. The
    /// caller owns deinitialization and deallocation.
    func allocateValueBuffer(minimumByteCount: Int = 1) -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer.allocate(
            byteCount: valueBufferByteCount(minimum: minimumByteCount),
            alignment: max(vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        )
    }
}

func abiClass(for type: Any.Type, isReturn: Bool = false) -> ABIClass {
    let metadata = reflect(type)
    let size = metadata.vwt.size
    if size == 0 {
        return .void
    }
    if isFloatingPoint(type) {
        return .floatingPoint
    }
    if let parts = directArgumentParts(for: type) {
        return .aggregate(parts: parts)
    }
    if size > 16 {
        if isReturn, let parts = directReturnParts(for: type) {
            return .aggregate(parts: parts)
        }
        return .indirect
    }
    return .integer(words: size > 8 ? 2 : 1)
}

func unsupportedRuntimeReason(
    for method: MethodDescriptor,
    architecture: RuntimeArchitecture
) -> String? {
    guard method.isAsync else { return nil }

    let registerLimit =
        switch architecture {
            case .arm64: 8
            case .x86_64: 6
        }

    // A generated witness also needs one general-purpose word for its receiver
    // across the async continuation boundary.
    var generalPurposeWords = 1
    if case .indirect = method.result.layout {
        generalPurposeWords += 1
    }
    if method.typedErrorUsesIndirectResultSlot {
        generalPurposeWords += 1
    }
    for argument in method.arguments {
        switch argument.value.layout {
            case .void, .floatingPoint:
                break
            case .integer(let words):
                generalPurposeWords += words
            case .aggregate(let parts):
                generalPurposeWords +=
                    parts
                    .filter { $0.register == .gp }
                    .count
            case .indirect:
                generalPurposeWords += 1
        }
    }

    guard generalPurposeWords >= registerLimit else { return nil }
    return "Its witness receiver, arguments, and hidden result storage consume all \(registerLimit) "
        + "\(architecture) general-purpose argument registers, crossing an "
        + "unsupported async continuation boundary. Use fewer integer-class "
        + "values or a hand-written test double."
}

func directArgumentParts(for type: Any.Type) -> [DirectValuePart]? {
    let metadata = reflect(type)
    guard metadata.vwt.size <= 4 * MemoryLayout<UInt>.size,
        let parts = directReturnParts(for: type),
        parts.contains(where: { $0.register == .fp })
            || (metadata.vwt.size > 2 * MemoryLayout<UInt>.size
                && containsFunctionStorage(type))
    else {
        return nil
    }
    return parts
}

private func containsFunctionStorage(
    _ type: Any.Type,
    visited: inout Set<UInt>
) -> Bool {
    let metadata = reflect(type)
    if metadata.kind == .function {
        return true
    }
    if let tuple = metadata as? TupleMetadata {
        return tuple.safelyInitializedElements.contains {
            containsFunctionStorage($0.type, visited: &visited)
        }
    }
    if metadata.kind == .optional,
        let optional = metadata as? EnumMetadata,
        let wrapped = optional.genericTypes.first
    {
        return containsFunctionStorage(wrapped, visited: &visited)
    }
    if let enumMetadata = metadata as? EnumMetadata,
        enumMetadata.descriptor.isReflectable
    {
        return enumMetadata.descriptor.fields.records.contains { field in
            field.hasMangledTypeName
                && enumMetadata.type(of: field.mangledTypeName).map {
                    containsFunctionStorage($0, visited: &visited)
                } == true
        }
    }
    guard let nominal = reflectStruct(type) else {
        return false
    }
    let key = UInt(bitPattern: nominal.ptr)
    guard visited.insert(key).inserted else {
        return false
    }
    defer { visited.remove(key) }
    return nominal.descriptor.fields.records.contains { field in
        field.hasMangledTypeName
            && nominal.type(of: field.mangledTypeName).map {
                containsFunctionStorage($0, visited: &visited)
            } == true
    }
}

private func containsFunctionStorage(_ type: Any.Type) -> Bool {
    var visited: Set<UInt> = []
    return containsFunctionStorage(type, visited: &visited)
}

func directReturnParts(for type: Any.Type) -> [DirectValuePart]? {
    var visited: Set<UInt> = []
    var parts: [DirectValuePart] = []
    guard appendDirectValueParts(for: type, baseOffset: 0, parts: &parts, visited: &visited),
        parts.isEmpty == false,
        parts.count <= 4,
        parts.filter({ $0.register == .gp }).count <= 4,
        parts.filter({ $0.register == .fp }).count <= 4
    else {
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

    if isFloat16(type) {
        parts.append(DirectValuePart(register: .fp, offset: baseOffset, byteCount: 2))
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

    if metadata.kind == .function, size <= 2 * MemoryLayout<UInt>.size {
        for offset in stride(from: 0, to: size, by: MemoryLayout<UInt>.size) {
            parts.append(
                DirectValuePart(
                    register: .gp,
                    offset: baseOffset + offset,
                    byteCount: min(MemoryLayout<UInt>.size, size - offset)
                )
            )
        }
        return true
    }

    // Loadable Swift enums use a fixed integer-register representation. Their
    // active payload and discriminator can share spare bits, so flatten the
    // final value bytes rather than trying to classify individual cases.
    if metadata is EnumMetadata,
        size <= 4 * MemoryLayout<UInt>.size
    {
        for offset in stride(from: 0, to: size, by: MemoryLayout<UInt>.size) {
            parts.append(
                DirectValuePart(
                    register: .gp,
                    offset: baseOffset + offset,
                    byteCount: min(MemoryLayout<UInt>.size, size - offset)
                )
            )
        }
        return true
    }

    if let tupleMetadata = metadata as? TupleMetadata {
        for element in tupleMetadata.safelyInitializedElements {
            guard
                appendDirectValueParts(
                    for: element.type,
                    baseOffset: baseOffset + element.offset,
                    parts: &parts,
                    visited: &visited
                )
            else {
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
            )
        else {
            return false
        }
    }
    return true
}
