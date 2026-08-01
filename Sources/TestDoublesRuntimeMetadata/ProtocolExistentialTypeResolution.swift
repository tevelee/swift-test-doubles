import Echo
import TestDoublesRuntimeSupport

func swiftTypeByNominalName(_ name: String) -> Any.Type? {
    if let prefix = nominalMangledPrefix(for: name) {
        for suffix in ["V", "O", "C"] {
            if let type = swiftTypeByMangledName(prefix + suffix) {
                return type
            }
            if let type = swiftTypeByExportedMetadataSymbol(prefix + suffix) {
                return type
            }
        }
    }
    return swiftProtocolExistentialType(named: name)
}

func protocolCompositionType(named name: String) -> Any.Type? {
    guard let scanner = DelimitedSyntaxScanner(name) else { return nil }
    let members = scanner.components(separatedBy: "&")
    guard members.count > 1 else { return nil }

    var isClassConstrained = false
    var descriptors: [ProtocolExistentialDescriptor] = []
    descriptors.reserveCapacity(members.count)
    for member in members {
        if member == "AnyObject" || member == "Swift.AnyObject" {
            isClassConstrained = true
            continue
        }
        if isRuntimeErasedProtocolMarker(member) {
            continue
        }
        guard let descriptor = protocolExistentialDescriptor(named: member) else {
            return nil
        }
        isClassConstrained = isClassConstrained || descriptor.isClassConstrained
        descriptors.append(descriptor)
    }
    guard descriptors.isEmpty == false else { return nil }
    return swiftProtocolExistentialType(
        from: descriptors,
        isClassConstrained: isClassConstrained
    )
}

private func nominalMangledPrefix(for name: String) -> String? {
    let parts = name.split(separator: ".").map(String.init)
    guard parts.count == 2 else { return nil }
    let module = parts[0]
    let typeName = parts[1]
    let modulePrefix = module == "Swift" ? "s" : "\(module.utf8.count)\(module)"
    return "\(modulePrefix)\(typeName.utf8.count)\(typeName)"
}

/// `Sendable` is a source-level marker protocol. Swift erases it before
/// materializing ordinary existential metadata, so no protocol descriptor is
/// available to pass to `swift_getExistentialTypeMetadata`.
private func isRuntimeErasedProtocolMarker(_ name: String) -> Bool {
    name == "Sendable" || name == "Swift.Sendable"
}

/// Function-signature demangling spells an ordinary existential as the
/// qualified protocol name, without the source-level `any` keyword. A protocol
/// declaration has no type metadata of its own, so resolve the compiler-emitted
/// descriptor and ask the Swift runtime to unique its one-protocol existential
/// metadata instead of guessing from layout.
private func swiftProtocolExistentialType(named name: String) -> Any.Type? {
    guard let descriptor = protocolExistentialDescriptor(named: name) else {
        return nil
    }
    return swiftProtocolExistentialType(
        from: [descriptor],
        isClassConstrained: descriptor.isClassConstrained
    )
}

private struct ProtocolExistentialDescriptor {
    let pointer: UnsafeRawPointer
    let isClassConstrained: Bool
}

private func protocolExistentialDescriptor(named name: String) -> ProtocolExistentialDescriptor? {
    if let prefix = nominalMangledPrefix(for: name),
        let descriptorPointer = RuntimeSymbols.rawSymbol(named: "$s\(prefix)Mp"),
        let descriptor = protocolExistentialDescriptor(
            at: UnsafeRawPointer(descriptorPointer)
        )
    {
        return descriptor
    }

    guard
        let descriptor = protocols.lazy.first(where: {
            qualifiedProtocolName($0) == name
        })
    else {
        return nil
    }
    return protocolExistentialDescriptor(at: descriptor.ptr)
}

private func protocolExistentialDescriptor(
    at descriptorPointer: UnsafeRawPointer
) -> ProtocolExistentialDescriptor? {
    guard
        let isClassConstrained = protocolDescriptorClassConstraint(
            at: descriptorPointer
        )
    else { return nil }
    return ProtocolExistentialDescriptor(
        pointer: descriptorPointer,
        isClassConstrained: isClassConstrained
    )
}

/// Protocol descriptors retain their full parent context even when their
/// linker symbol uses mangling substitutions. Compare that semantic name when
/// a source spelling names a nested protocol instead of attempting to recreate
/// every nested mangling form.
private func qualifiedProtocolName(_ descriptor: ProtocolDescriptor) -> String? {
    var components = [descriptor.name]
    var context = descriptor.parent
    while let current = context {
        if let module = current as? ModuleDescriptor {
            components.append(module.name)
            return components.reversed().joined(separator: ".")
        }
        if let type = current as? any TypeContextDescriptor {
            components.append(type.name)
            context = type.parent
            continue
        }
        if let parentProtocol = current as? ProtocolDescriptor {
            components.append(parentProtocol.name)
            context = parentProtocol.parent
            continue
        }
        return nil
    }
    return nil
}

private func swiftProtocolExistentialType(
    from descriptors: [ProtocolExistentialDescriptor],
    isClassConstrained: Bool
) -> Any.Type? {
    guard let swiftGetExistentialTypeMetadata else { return nil }
    var protocols = descriptors.map(\.pointer)
    let metadata: UnsafeRawPointer? = protocols.withUnsafeMutableBufferPointer { protocols in
        guard let baseAddress = protocols.baseAddress else { return nil }
        return swiftGetExistentialTypeMetadata(
            !isClassConstrained,
            nil,
            protocols.count,
            baseAddress
        )
    }
    return metadata.map { unsafeBitCast($0, to: Any.Type.self) }
}

/// The first word of a protocol descriptor is `ContextDescriptorFlags`. The
/// protocol kind must be `3`; the first kind-specific bit stores the inverted
/// `ProtocolClassConstraint` value, where zero means class-constrained.
private func protocolDescriptorClassConstraint(at pointer: UnsafeRawPointer) -> Bool? {
    let flags = pointer.loadUnaligned(as: UInt32.self)
    guard flags & 0x1F == 3 else { return nil }
    return flags & 0x10000 == 0
}

/// Public noncopyable nominal types expose concrete metadata even though the
/// runtime's generic mangled-name lookup intentionally declines to instantiate
/// them. Swift's exported `N` symbol is the metadata object itself.
private func swiftTypeByExportedMetadataSymbol(_ mangledType: String) -> Any.Type? {
    let symbolName = "$s\(mangledType)N"
    guard let metadata = RuntimeSymbols.rawSymbol(named: symbolName) else { return nil }
    return unsafeBitCast(metadata, to: Any.Type.self)
}

func swiftTypeByMangledName(_ name: String) -> Any.Type? {
    guard let swiftGetTypeByMangledNameInContext else {
        return nil
    }
    return name.utf8CString.withUnsafeBufferPointer { buffer -> Any.Type? in
        guard let base = buffer.baseAddress else { return nil }
        guard
            let metadata = swiftGetTypeByMangledNameInContext(
                UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
                UInt(name.utf8.count),
                nil,
                nil
            )
        else {
            return nil
        }
        return unsafeBitCast(metadata, to: Any.Type.self)
    }
}

private typealias SwiftGetTypeByMangledNameInContext =
    @convention(c) (
        UnsafePointer<UInt8>,
        UInt,
        UnsafeRawPointer?,
        UnsafeRawPointer?
    ) -> UnsafeRawPointer?

private var swiftGetTypeByMangledNameInContext: SwiftGetTypeByMangledNameInContext? {
    RuntimeSymbols.function(named: "swift_getTypeByMangledNameInContext")
}

private typealias SwiftGetExistentialTypeMetadata =
    @convention(c) (
        Bool,
        UnsafeRawPointer?,
        Int,
        UnsafePointer<UnsafeRawPointer>
    ) -> UnsafeRawPointer

private var swiftGetExistentialTypeMetadata: SwiftGetExistentialTypeMetadata? {
    RuntimeSymbols.function(named: "swift_getExistentialTypeMetadata")
}
