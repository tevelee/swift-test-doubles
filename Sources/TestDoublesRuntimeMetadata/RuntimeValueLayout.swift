// Swift ABI classification used by the runtime trampoline.
import Echo
import Foundation
import TestDoublesRuntimeSupport

package enum ABIClass: Sendable {
    case void
    case integer(words: Int)
    case floatingPoint
    case aggregate(parts: [DirectValuePart])
    case indirect
}

package enum DirectValueRegister: Equatable, Sendable {
    case gp
    case fp
}

package struct DirectValuePart: Sendable {
    package let register: DirectValueRegister
    package let offset: Int
    package let byteCount: Int

    /// Loads this part's bytes from in-memory value storage into a register word.
    package func load(from source: UnsafeRawPointer) -> UInt64 {
        precondition(
            byteCount <= MemoryLayout<UInt64>.size,
            "[TestDoubles] A scalar register word cannot load a wider vector value."
        )
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
    package func store(_ value: UInt64, into destination: UnsafeMutableRawPointer) {
        precondition(
            byteCount <= MemoryLayout<UInt64>.size,
            "[TestDoubles] A scalar register word cannot store a wider vector value."
        )
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

package func abiClass(for type: Any.Type, isReturn: Bool = false) -> ABIClass {
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

/// Whether an `InlineArray` specialization's fixed storage contains values
/// that can safely cross the recorder's `Any` boundary.
package func inlineArrayHasCopyableElements(_ type: Any.Type) -> Bool {
    guard let storage = inlineArrayStorage(in: type) else { return false }
    return reflect(storage.elementType).vwt.flags.isCopyable
}

private struct InlineArrayStorage {
    let type: Any.Type
    let elementType: Any.Type
}

private func inlineArrayStorage(in type: Any.Type) -> InlineArrayStorage? {
    guard let metadata = reflectStruct(type),
        metadata.descriptor.name == "InlineArray",
        (metadata.descriptor.parent as? ModuleDescriptor)?.name == "Swift"
    else {
        return nil
    }

    let arguments = metadata.genericArguments
    guard arguments.count == 2,
        case .value(let count) = arguments[0],
        let realizedCount = Int(exactly: count),
        case .metadata(let elementType) = arguments[1]
    else {
        return nil
    }

    let fields = metadata.descriptor.fields.records
    guard fields.count == 1,
        let field = fields.first,
        field.name == "_storage",
        field.hasMangledTypeName,
        let fieldType = runtimeFieldType(
            field.mangledTypeName,
            in: metadata,
            genericArgumentWords: [
                count,
                UInt(
                    bitPattern: unsafeBitCast(
                        elementType,
                        to: UnsafeRawPointer.self
                    )
                )
            ]
        )
    else {
        return nil
    }

    switch realizedCount {
        case 0:
            guard ObjectIdentifier(fieldType) == ObjectIdentifier(Void.self)
            else {
                return nil
            }
        case 1:
            guard
                ObjectIdentifier(fieldType) == ObjectIdentifier(elementType)
            else {
                return nil
            }
        default:
            guard let fixedArray = reflect(fieldType) as? FixedArrayMetadata,
                fixedArray.count == realizedCount,
                ObjectIdentifier(fixedArray.elementType)
                    == ObjectIdentifier(elementType)
            else {
                return nil
            }
    }
    return InlineArrayStorage(type: fieldType, elementType: elementType)
}

/// Resolves a field type directly against one concrete metadata instance.
///
/// Echo's general field-name cache is keyed by the descriptor's shared
/// symbolic mangling, so a value-generic field can otherwise reuse the first
/// specialization's `Builtin.FixedArray` metadata for later InlineArray
/// counts or element types.
private func runtimeFieldType(
    _ mangledName: UnsafeRawPointer,
    in metadata: StructMetadata,
    genericArgumentWords: [UInt]
) -> Any.Type? {
    guard let swiftGetTypeByMangledNameInContextForValueLayout else {
        return nil
    }
    let length = symbolicMangledNameLength(mangledName)
    return genericArgumentWords.withUnsafeBufferPointer { words in
        guard
            let pointer = swiftGetTypeByMangledNameInContextForValueLayout(
                mangledName.assumingMemoryBound(to: UInt8.self),
                UInt(length),
                metadata.descriptor.ptr,
                words.baseAddress.map(UnsafeRawPointer.init)
            )
        else {
            return nil
        }
        return unsafeBitCast(pointer, to: Any.Type.self)
    }
}

private func symbolicMangledNameLength(_ base: UnsafeRawPointer) -> Int {
    var end = base
    while end.load(as: UInt8.self) != 0 {
        let current = end.load(as: UInt8.self)
        end += 1
        if current >= 0x1 && current <= 0x17 {
            end += 4
        } else if current >= 0x18 && current <= 0x1F {
            end += MemoryLayout<Int>.size
        }
    }
    return end - base
}

private typealias SwiftGetTypeByMangledNameInContextForValueLayout =
    @convention(c) (
        UnsafePointer<UInt8>,
        UInt,
        UnsafeRawPointer?,
        UnsafeRawPointer?
    ) -> UnsafeRawPointer?

private var swiftGetTypeByMangledNameInContextForValueLayout: SwiftGetTypeByMangledNameInContextForValueLayout? {
    RuntimeSymbols.function(named: "swift_getTypeByMangledNameInContext")
}

/// Whether `type` is a concrete SIMD shape proven to use one complete 128-bit
/// vector register for both arguments and results on arm64 and x86_64, and if
/// so, the byte count of that register (always 16).
///
/// Computed generically instead of enumerated: any concrete `SIMD` type whose
/// total storage is exactly 16 bytes with every one of those bytes backing a
/// real lane qualifies, regardless of width or scalar. Smaller vectors are
/// intentionally excluded: Swift can scalarize them or use different register
/// layouts across the two architectures. Padded three-lane vectors are
/// excluded as well (`scalarCount * scalar stride` falls short of the 16-byte
/// storage size) so this boundary transports only complete lane payloads with
/// no unspecified bytes.
package func concreteSIMDRegisterByteCount(for type: Any.Type) -> Int? {
    guard let simdType = type as? any SIMD.Type else { return nil }
    return _openExistential(simdType, do: openedConcreteSIMDRegisterByteCount)
}

private func openedConcreteSIMDRegisterByteCount<T: SIMD>(_: T.Type) -> Int? {
    let size = MemoryLayout<T>.size
    guard size == 16, T().scalarCount * MemoryLayout<T.Scalar>.stride == size
    else {
        return nil
    }
    return size
}

package func directArgumentParts(for type: Any.Type) -> [DirectValuePart]? {
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
    if let fixedArray = metadata as? FixedArrayMetadata {
        return containsFunctionStorage(
            fixedArray.elementType,
            visited: &visited
        )
    }
    if let fixedArray = inlineArrayStorage(in: type) {
        return containsFunctionStorage(
            fixedArray.type,
            visited: &visited
        )
    }
    if let tuple = metadata as? TupleMetadata {
        return tuple.elements.contains {
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

package func directReturnParts(for type: Any.Type) -> [DirectValuePart]? {
    if let byteCount = concreteSIMDRegisterByteCount(for: type) {
        return [
            DirectValuePart(
                register: .fp,
                offset: 0,
                byteCount: byteCount
            )
        ]
    }
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
    // Direct concrete SIMD is classified before recursive aggregate
    // decomposition. A SIMD nested in another value is not ABI-equivalent to
    // that top-level vector and remains unsupported.
    if type is any SIMD.Type {
        return false
    }
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

    if metadata.kind == .class || metadata.kind == .foreignClass
        || metadata.kind == .foreignReferenceType
    {
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
        for element in tupleMetadata.elements {
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

    if let fixedArray = metadata as? FixedArrayMetadata {
        guard fixedArray.count >= 0,
            fixedArray.elementMetadata.vwt.flags.isCopyable
        else {
            return false
        }
        if fixedArray.realizedCount == 0
            || fixedArray.elementMetadata.vwt.size == 0
        {
            return true
        }
        for index in 0 ..< fixedArray.realizedCount {
            guard
                appendDirectValueParts(
                    for: fixedArray.elementType,
                    baseOffset:
                        baseOffset
                        + index * fixedArray.elementMetadata.vwt.stride,
                    parts: &parts,
                    visited: &visited
                ),
                parts.count <= 4,
                parts.filter({ $0.register == .gp }).count <= 4,
                parts.filter({ $0.register == .fp }).count <= 4
            else {
                return false
            }
        }
        return true
    }

    if let fixedArray = inlineArrayStorage(in: type) {
        return appendDirectValueParts(
            for: fixedArray.type,
            baseOffset: baseOffset,
            parts: &parts,
            visited: &visited
        )
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
