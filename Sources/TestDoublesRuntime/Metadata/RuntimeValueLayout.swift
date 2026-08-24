// Swift ABI classification used by the runtime trampoline.
import Echo
import Foundation

package enum ABIClass: Equatable, Sendable {
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

package struct DirectValuePart: Equatable, Sendable {
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

package func abiClass(for type: Any.Type) -> ABIClass {
    let metadata = reflect(type)
    let size = metadata.vwt.size
    if size == 0 {
        return .void
    }
    if isFloatingPoint(type) {
        return .floatingPoint
    }
    if let parts = directArgumentParts(for: type), parts.isEmpty == false {
        return .aggregate(parts: parts)
    }
    if size > 16 {
        // Swift explodes a loadable aggregate into registers whether it is
        // returned or passed, and only spills to an indirect address once the
        // explosion no longer fits. Classifying an argument as indirect while
        // the caller passed it in registers reads a field as an address.
        if let parts = directReturnParts(for: type) {
            return .aggregate(parts: parts)
        }
        return .indirect
    }
    return .integer(words: size > 8 ? 2 : 1)
}

/// Every argument transport still compatible with the metadata available at
/// runtime.
///
/// Swift 6.3 marks nominal value types that may need stable storage with
/// `isAddressableForDependencies`, but that value-witness bit does not encode
/// whether a client sees the declaration as frozen. This also applies to a
/// standard-library generic shell whose concrete arguments come from a
/// resilient module, such as `ClosedRange<Date>`. Runtime metadata therefore
/// admits both the loadable layout and the resilient client convention. The
/// invocation boundary must calibrate those alternatives before typed
/// decoding.
package func argumentABIClassCandidates(for type: Any.Type) -> [ABIClass] {
    var context = ArgumentABIClassificationContext()
    return context.candidates(for: type)
}

/// Whether a top-level tuple contains an ABI-ambiguous member.
///
/// `ABIClass` can model a whole value as either direct or indirect. Swift
/// lowers tuple elements independently, though, so `(ResilientValue, Int)`
/// has a mixed transport: an address for the first element and a register for
/// the second. That cannot be represented by one `ABIClass`; callers must
/// reject the shape until they have a member-level transport plan.
package func requiresStructuralABITransport(for type: Any.Type) -> Bool {
    var context = ArgumentABIClassificationContext()
    return context.requiresStructuralTransport(for: type)
}

/// Whether runtime metadata cannot select one decodable argument transport.
///
/// An uncertain whole-value convention can be calibrated from recording bytes.
/// A structural tuple convention instead requires a member-level plan, which
/// the runtime does not yet implement. Callers that cannot calibrate either
/// form use this shared predicate to reject the type before decoding.
package func hasUncertainArgumentABITransport(for type: Any.Type) -> Bool {
    var context = ArgumentABIClassificationContext()
    return context.hasUncertainTransport(for: type)
}

/// Recursively classifies a value while breaking metadata cycles. Recursive
/// generic enums can record their own specialization in a field descriptor;
/// revisiting that edge adds no new evidence, so it retains the direct layout
/// already observed for the active type.
private struct ArgumentABIClassificationContext {
    private var activeTypes: Set<ObjectIdentifier> = []

    mutating func candidates(for type: Any.Type) -> [ABIClass] {
        let direct = abiClass(for: type)

        let identifier = ObjectIdentifier(type)
        guard activeTypes.insert(identifier).inserted else { return [direct] }
        defer { activeTypes.remove(identifier) }

        let isAddressableForDependencies: Bool
        let hasOpaqueStandardLibraryDirectLayout: Bool
        if let metadata = reflectStruct(type) {
            isAddressableForDependencies = hasAddressableArgumentDependencies(in: metadata)
            hasOpaqueStandardLibraryDirectLayout =
                hasOpaqueStandardLibraryDirectCandidate(
                    metadata.descriptor,
                    directLayout: direct
                )
        } else if let metadata = reflectEnum(type) {
            isAddressableForDependencies = hasAddressableArgumentDependencies(in: metadata)
            hasOpaqueStandardLibraryDirectLayout =
                hasOpaqueStandardLibraryDirectCandidate(
                    metadata.descriptor,
                    directLayout: direct
                )
        } else {
            isAddressableForDependencies = false
            hasOpaqueStandardLibraryDirectLayout = false
        }
        if direct == .indirect,
            isAddressableForDependencies || hasOpaqueStandardLibraryDirectLayout,
            let scalarDirect = scalarDirectArgumentLayout(for: type)
        {
            return [scalarDirect, direct]
        }
        guard isAddressableForDependencies else { return [direct] }
        guard direct != .indirect else { return [direct] }
        return [direct, .indirect]
    }

    mutating func requiresStructuralTransport(for type: Any.Type) -> Bool {
        guard let tuple = reflect(type) as? TupleMetadata else { return false }
        return tuple.elements.contains { element in
            hasUncertainTransport(for: element.type)
        }
    }

    mutating func hasUncertainTransport(for type: Any.Type) -> Bool {
        candidates(for: type).count > 1
            || requiresStructuralTransport(for: type)
    }

    private mutating func hasAddressableArgumentDependencies(
        in metadata: StructMetadata
    ) -> Bool {
        (metadata.vwt.flags.isAddressableForDependencies
            && definingModuleName(of: metadata.descriptor.parent) != "Swift")
            // Runtime metadata does not record whether an imported generic
            // nominal was declared `@frozen`. Its field can therefore look
            // loadable even though a library-evolution client passes the
            // outer value by address. Calibrate both whole-value conventions
            // for every non-standard-library generic nominal rather than
            // guessing from the concrete argument's layout.
            || isGenericNominalOutsideSwift(metadata.descriptor)
            || storesAddressableGenericArgument(in: metadata)
    }

    private mutating func hasAddressableArgumentDependencies(
        in metadata: EnumMetadata
    ) -> Bool {
        (metadata.vwt.flags.isAddressableForDependencies
            && definingModuleName(of: metadata.descriptor.parent) != "Swift")
            || isGenericNominalOutsideSwift(metadata.descriptor)
            || storesAddressableGenericArgument(in: metadata)
    }

    private func isGenericNominalOutsideSwift(
        _ descriptor: any TypeContextDescriptor
    ) -> Bool {
        descriptor.flags.isGeneric
            && definingModuleName(of: descriptor.parent) != "Swift"
    }

    /// Some standard-library generic values reveal neither a reflected field
    /// decomposition nor a value-witness discriminator for their scalar
    /// direct ABI. A generic value with that opaque, apparently indirect shape
    /// must retain both candidates until recording observes the client call.
    private func hasOpaqueStandardLibraryDirectCandidate(
        _ descriptor: any TypeContextDescriptor,
        directLayout: ABIClass
    ) -> Bool {
        descriptor.flags.isGeneric
            && definingModuleName(of: descriptor.parent) == "Swift"
            && directLayout == .indirect
    }

    /// Some standard-library generic values expose only their fixed byte
    /// layout, not field records the reflection decoder can flatten. A
    /// loadable client may still lower up to four scalar words directly. This
    /// is a calibration candidate, not a claim about the metadata's preferred
    /// transport: a matching recording frame supplies the proof before it is
    /// ever decoded as a value.
    private func scalarDirectArgumentLayout(for type: Any.Type) -> ABIClass? {
        let size = reflect(type).vwt.size
        let wordSize = MemoryLayout<UInt>.size
        guard size > 0, size <= 4 * wordSize else { return nil }
        return .aggregate(
            parts: stride(from: 0, to: size, by: wordSize).map { offset in
                DirectValuePart(
                    register: .gp,
                    offset: offset,
                    byteCount: min(wordSize, size - offset)
                )
            }
        )
    }

    private mutating func storesAddressableGenericArgument(
        in metadata: StructMetadata
    ) -> Bool {
        guard metadata.descriptor.flags.isGeneric else { return false }
        return metadata.descriptor.fields.records.contains { field in
            guard field.hasMangledTypeName,
                let fieldType = resolvedFieldType(
                    field.mangledTypeName,
                    in: metadata
                )
            else {
                return false
            }
            // A known-indirect implementation detail, such as SIMD's internal
            // storage type, does not make the outer generic value ABI-uncertain.
            // Propagate a field whose own client transport is ambiguous, including
            // a tuple whose individually lowered members make the enclosing
            // generic shell ABI-uncertain.
            return hasUncertainTransport(for: fieldType)
        }
    }

    private mutating func storesAddressableGenericArgument(
        in metadata: EnumMetadata
    ) -> Bool {
        guard metadata.descriptor.flags.isGeneric else { return false }
        return metadata.descriptor.fields.records.contains { field in
            guard field.hasMangledTypeName,
                let fieldType = resolvedFieldType(
                    field.mangledTypeName,
                    in: metadata
                )
            else {
                return false
            }
            // See the struct overload above: propagate uncertainty, not a known
            // indirect storage layout.
            return hasUncertainTransport(for: fieldType)
        }
    }
}

private func definingModuleName(of parent: ContextDescriptor?) -> String? {
    var context = parent
    while let current = context {
        if let module = current as? ModuleDescriptor {
            return module.name
        }
        if let type = current as? any TypeContextDescriptor {
            context = type.parent
        } else if let parentProtocol = current as? ProtocolDescriptor {
            context = parentProtocol.parent
        } else {
            return nil
        }
    }
    return nil
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
            context: metadata.descriptor.ptr,
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
/// Echo's general field-name cache is keyed only by the descriptor's shared
/// symbolic mangling. Resolve against this exact metadata instance instead so
/// one generic specialization cannot reuse another's field type.
private func runtimeFieldType(
    _ mangledName: UnsafeRawPointer,
    context: UnsafeRawPointer,
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
                context,
                words.baseAddress.map(UnsafeRawPointer.init)
            )
        else {
            return nil
        }
        return unsafeBitCast(pointer, to: Any.Type.self)
    }
}

/// Resolves a stored-field type against the exact generic specialization.
///
/// Echo's general symbolic-mangling cache is descriptor-scoped, but a generic
/// descriptor is shared by all of its specializations. Callers that inspect
/// stored fields must use this resolver to avoid leaking one specialization's
/// layout into another.
package func resolvedFieldType(
    _ mangledName: UnsafeRawPointer,
    in metadata: StructMetadata
) -> Any.Type? {
    guard metadata.descriptor.flags.isGeneric else {
        return metadata.type(of: mangledName)
    }
    guard let arguments = genericArgumentWords(metadata.genericArguments) else {
        return nil
    }
    return runtimeFieldType(
        mangledName,
        context: metadata.descriptor.ptr,
        genericArgumentWords: arguments
    )
}

package func resolvedFieldType(
    _ mangledName: UnsafeRawPointer,
    in metadata: EnumMetadata
) -> Any.Type? {
    guard metadata.descriptor.flags.isGeneric else {
        return metadata.type(of: mangledName)
    }
    guard let arguments = genericArgumentWords(metadata.genericArguments) else {
        return nil
    }
    return runtimeFieldType(
        mangledName,
        context: metadata.descriptor.ptr,
        genericArgumentWords: arguments
    )
}

private func genericArgumentWords(
    _ arguments: [GenericArgument]
) -> [UInt]? {
    arguments.map { argument in
        switch argument {
            case .packLength(let length):
                return UInt(bitPattern: length)
            case .metadata(let type):
                return UInt(
                    bitPattern: unsafeBitCast(type, to: UnsafeRawPointer.self)
                )
            case .metadataPack(let pointer), .witnessTablePack(let pointer):
                return UInt(bitPattern: pointer)
            case .witnessTable(let table):
                return UInt(bitPattern: table.ptr)
            case .value(let value):
                return value
        }
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

/// Matches the C trampoline frame's return slots. Wider results already use
/// Swift's own indirect `sret` convention.
private let maximumDirectSIMDRegisterCount =
    TrampolineABICapacity.directReturnRegisterCount

/// Whether `type` is a concrete SIMD shape using one or more complete
/// 128-bit vector registers, and if so, its total byte count.
///
/// Sub-16-byte vectors are excluded: Swift scalarizes them differently per
/// architecture (`SIMD2<Float>` is one vector register on arm64 but two
/// scalar registers on x86_64), which this architecture-independent part
/// computation can't represent. Padded vectors (`scalarCount * scalarStride`
/// short of the storage size) are excluded too.
package func concreteSIMDRegisterByteCount(for type: Any.Type) -> Int? {
    guard let simdType = type as? any SIMD.Type else { return nil }
    return _openExistential(simdType, do: openedConcreteSIMDRegisterByteCount)
}

private func openedConcreteSIMDRegisterByteCount<T: SIMD>(_: T.Type) -> Int? {
    let size = MemoryLayout<T>.size
    guard size >= 16, size.isMultiple(of: 16),
        size <= maximumDirectSIMDRegisterCount * 16,
        T().scalarCount * MemoryLayout<T.Scalar>.stride == size
    else {
        return nil
    }
    return size
}

package func directArgumentParts(for type: Any.Type) -> [DirectValuePart]? {
    if let byteCount = concreteSIMDRegisterByteCount(for: type) {
        return stride(from: 0, to: byteCount, by: 16).map {
            DirectValuePart(register: .fp, offset: $0, byteCount: 16)
        }
    }
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
                && resolvedFieldType(field.mangledTypeName, in: enumMetadata).map {
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
            && resolvedFieldType(field.mangledTypeName, in: nominal).map {
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
        return stride(from: 0, to: byteCount, by: 16).map {
            DirectValuePart(register: .fp, offset: $0, byteCount: 16)
        }
    }
    var visited: Set<UInt> = []
    var scalars: [DirectValuePart] = []
    guard appendDirectValueParts(for: type, baseOffset: 0, parts: &scalars, visited: &visited)
    else {
        return nil
    }
    let parts = wholeIntegerWords(scalars, size: reflect(type).vwt.size)
    guard parts.isEmpty == false,
        parts.count <= 4,
        parts.filter({ $0.register == .gp }).count <= 4,
        parts.filter({ $0.register == .fp }).count <= 4
    else {
        return nil
    }
    return parts
}

/// Rewrites an all-integer explosion as the machine words it actually occupies.
///
/// Swift legalizes a value's scalars into native register types before passing
/// or returning it, so `{ Int32, Int32 }` takes one register rather than two.
/// Counting unpacked scalars overstates the register demand, and carrying their
/// individual offsets drops any byte no field reports, such as the leading
/// bitfield storage of `Decimal`. Values holding a floating-point field keep
/// their per-field parts, because those fields travel in their own registers.
private func wholeIntegerWords(
    _ parts: [DirectValuePart],
    size: Int
) -> [DirectValuePart] {
    let wordSize = MemoryLayout<UInt>.size
    guard parts.count > 1, parts.allSatisfy({ $0.register == .gp }), size > 0 else {
        return parts
    }
    return stride(from: 0, to: size, by: wordSize).map { offset in
        DirectValuePart(
            register: .gp,
            offset: offset,
            byteCount: min(wordSize, size - offset)
        )
    }
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
            let resolvedFieldType = resolvedFieldType(
                field.mangledTypeName,
                in: structMetadata
            ),
            appendDirectValueParts(
                for: resolvedFieldType,
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
