import Echo

/// The exact ordinary and extended existential metadata subset supported by
/// runtime stubs.
struct StubProtocolMetadata {
    struct AssociatedTypeBinding {
        let protocolDescriptor: ProtocolDescriptor
        let name: String
        let type: Any.Type
    }
    let protocols: [ProtocolDescriptor]
    let numberOfWitnessTables: Int
    let isClassConstrained: Bool
    let hasSuperclassConstraint: Bool
    let superclass: Any.Type?
    let specialProtocol: SpecialProtocol
    /// Concrete metadata arguments supplied by an accepted extended
    /// existential shape, keyed by the descriptor and associated-type name
    /// encoded in each same-type requirement.
    let associatedTypeBindings: [AssociatedTypeBinding]
}

func inspectStubProtocolMetadata(
    _ type: Any.Type,
    typeDescription: String
) throws -> StubProtocolMetadata {
    let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
    switch metadata.load(as: UInt.self) {
        case 0x303:
            guard let existential = reflect(type) as? ExistentialMetadata else {
                throw StubError.typeIsNotProtocol(typeDescription: typeDescription)
            }
            return StubProtocolMetadata(
                protocols: existential.protocols,
                numberOfWitnessTables: existential.flags.numWitnessTables,
                isClassConstrained: existential.flags.isClassConstraint,
                hasSuperclassConstraint: existential.flags.hasSuperclassConstraint,
                superclass: existential.superclass,
                specialProtocol: existential.flags.specialProtocol,
                associatedTypeBindings: []
            )
        case 0x307:
            return try inspectExtendedExistential(metadata, typeDescription: typeDescription)
        default:
            throw StubError.typeIsNotProtocol(typeDescription: typeDescription)
    }
}

private struct GenericSignatureHeader {
    let numberOfParameters: UInt16
    let numberOfRequirements: UInt16
    let numberOfKeyArguments: UInt16
    let flags: UInt16
}

private func inspectExtendedExistential(
    _ metadata: UnsafeRawPointer,
    typeDescription: String
) throws -> StubProtocolMetadata {
    let shape = metadata.load(fromByteOffset: 8, as: UnsafeRawPointer.self)
    let flags = shape.load(as: UInt32.self)
    let specialKind = flags & 0xff
    guard specialKind == 0 || specialKind == 1,
        flags & ~UInt32(0xff) == 0x1900
    else {
        throw StubError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "This extended existential is outside the supported bound-associated-type metadata shape. Only opaque or class-constrained existentials with concretely bound primary associated types are supported."
        )
    }
    // TargetExtendedExistentialTypeShape starts with 32-bit flags, a 32-bit
    // relative existential-type pointer, and the requirement signature
    // header. This accepted flag set then has one generalization header and no
    // type expression, suggested witnesses, explicit parameter descriptors,
    // or pack descriptors before the generic requirements.
    let requirementHeader = (shape + 8).load(as: GenericSignatureHeader.self)
    let generalizationHeader = (shape + 16).load(as: GenericSignatureHeader.self)
    let requirements = shape + 24
    let unsupportedSuperclassReason =
        "Superclass-constrained bound associated-type existentials are not supported. Use an AnyObject-constrained protocol when the concrete superclass is not required."
    for index in 0 ..< Int(requirementHeader.numberOfRequirements) {
        let requirement = requirements + index * 12
        if requirement.load(as: UInt32.self) == 0x02 {
            throw StubError.unsupportedProtocolShape(
                protocolName: typeDescription,
                reason: unsupportedSuperclassReason
            )
        }
    }
    let numberOfBindings = Int(generalizationHeader.numberOfParameters)
    guard numberOfBindings > 0,
        Int(requirementHeader.numberOfParameters) == numberOfBindings + 1,
        requirementHeader.numberOfRequirements > 0,
        Int(requirementHeader.numberOfKeyArguments) == Int(requirementHeader.numberOfRequirements) + 1,
        requirementHeader.flags == 0,
        generalizationHeader.numberOfKeyArguments == generalizationHeader.numberOfParameters,
        generalizationHeader.flags == 0
    else {
        throw StubError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "Bound associated-type support requires a metadata-only generalization argument for every concrete primary-associated-type binding."
        )
    }
    var protocols: [ProtocolDescriptor] = []
    var associatedTypeIdentities:
        [(
            protocolDescriptor: ProtocolDescriptor,
            name: String
        )] = []
    for index in 0 ..< Int(requirementHeader.numberOfRequirements) {
        let requirement = requirements + index * 12
        let requirementFlags = requirement.load(as: UInt32.self)
        // Accepted protocol requirements contribute a key witness argument
        // (0x80). Concrete bindings are plain same-type requirements (0x01).
        // Reject extra/key bits on either kind.
        switch requirementFlags {
            case 0x80:
                protocols.append(
                    unsafeBitCast(
                        resolveRelativeIndirectablePointer(at: requirement + 8),
                        to: ProtocolDescriptor.self
                    ))
            case 0x01:
                guard associatedTypeIdentities.count < numberOfBindings,
                    mangledGenericParameter(
                        at: resolveRelativeDirectPointer(at: requirement + 4)
                    ) == associatedTypeIdentities.count,
                    let identity = parseAssociatedTypeReference(
                        at: resolveRelativeDirectPointer(at: requirement + 8),
                        suffix: [0x51, 0x79, 0x64, 0x5f, 0x5f]
                    )
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: typeDescription,
                        reason: "Concrete associated-type bindings are not in a supported deterministic metadata-argument order."
                    )
                }
                associatedTypeIdentities.append(identity)
            case 0x02:
                throw StubError.unsupportedProtocolShape(
                    protocolName: typeDescription,
                    reason: unsupportedSuperclassReason
                )
            default:
                throw StubError.unsupportedProtocolShape(
                    protocolName: typeDescription,
                    reason: "The bound associated-type requirement signature contains unsupported generic requirement flags."
                )
        }
    }
    let protocolIDs = protocols.map { UInt(bitPattern: $0.ptr) }
    let bindingIDs = associatedTypeIdentities.map {
        AssociatedTypeID(
            protocolDescriptor: $0.protocolDescriptor,
            name: $0.name
        )
    }
    guard protocols.isEmpty == false,
        Set(protocolIDs).count == protocols.count,
        associatedTypeIdentities.count == numberOfBindings,
        Set(bindingIDs).count == associatedTypeIdentities.count,
        Int(requirementHeader.numberOfRequirements) == protocols.count + numberOfBindings,
        Int(requirementHeader.numberOfKeyArguments) == protocols.count + numberOfBindings + 1
    else {
        throw StubError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "Bound associated-type support requires one same-type binding per metadata argument and one witness-table requirement per distinct root protocol."
        )
    }
    // TargetExtendedExistentialTypeMetadata is kind, shape, then the
    // generalization argument vector. `NumKeyArguments == NumParams` proves
    // this vector contains metadata only, even when trailing generalization
    // requirements describe non-key Copyable constraints. Those trailing
    // requirements begin after the requirement-signature descriptors and are
    // deliberately not interpreted here.
    let wordSize = MemoryLayout<UnsafeRawPointer>.size
    let associatedTypeBindings = associatedTypeIdentities.enumerated().map {
        index, identity in
        let boundMetadata = metadata.load(
            fromByteOffset: 16 + index * wordSize,
            as: UnsafeRawPointer.self
        )
        return StubProtocolMetadata.AssociatedTypeBinding(
            protocolDescriptor: identity.protocolDescriptor,
            name: identity.name,
            type: unsafeBitCast(boundMetadata, to: Any.Type.self)
        )
    }
    return StubProtocolMetadata(
        protocols: protocols,
        numberOfWitnessTables: protocols.count,
        isClassConstrained: specialKind == 1,
        hasSuperclassConstraint: false,
        superclass: nil,
        specialProtocol: .none,
        associatedTypeBindings: associatedTypeBindings
    )
}

/// Returns the associated-type identity encoded by the supported dependent
/// member mangling used in a protocol requirement signature.
func parseProtocolAssociatedTypeReference(
    at mangledName: UnsafeRawPointer
) -> (protocolDescriptor: ProtocolDescriptor, name: String)? {
    parseAssociatedTypeReference(
        at: mangledName,
        suffix: [0x51, 0x7a]
    )
}

private func parseAssociatedTypeReference(
    at mangledName: UnsafeRawPointer,
    suffix: [UInt8]
) -> (protocolDescriptor: ProtocolDescriptor, name: String)? {
    var cursor = mangledName
    var nameLength = 0
    var digitCount = 0
    while true {
        let byte = cursor.load(as: UInt8.self)
        guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
            break
        }
        if digitCount == 0, byte == UInt8(ascii: "0") { return nil }
        guard nameLength <= 1_000 else { return nil }
        nameLength = nameLength * 10 + Int(byte - UInt8(ascii: "0"))
        digitCount += 1
        cursor += 1
    }
    guard digitCount > 0, nameLength > 0 else { return nil }
    let nameBytes = UnsafeRawBufferPointer(start: cursor, count: nameLength)
    guard let name = String(bytes: nameBytes, encoding: .utf8) else { return nil }
    cursor += nameLength

    // Swift may encode the context descriptor as a direct (0x01) or indirect
    // (0x02) symbolic reference.
    let directness = cursor.load(as: UInt8.self)
    guard directness == 0x01 || directness == 0x02 else { return nil }
    let descriptorReference = cursor + 1
    let descriptorTarget =
        descriptorReference
        + Int(
            descriptorReference.loadUnaligned(as: Int32.self)
        )
    let descriptorPointer =
        directness == 0x01
        ? descriptorTarget
        : descriptorTarget.load(as: UnsafeRawPointer.self)
    cursor += 5

    for expected in suffix {
        guard cursor.load(as: UInt8.self) == expected else { return nil }
        cursor += 1
    }
    guard cursor.load(as: UInt8.self) == 0 else { return nil }
    return (
        unsafeBitCast(descriptorPointer, to: ProtocolDescriptor.self),
        name
    )
}

private func mangledGenericParameter(at name: UnsafeRawPointer) -> Int? {
    let string = String(cString: name.assumingMemoryBound(to: CChar.self))
    if string == "x" { return 0 }
    if string == "q_" { return 1 }
    guard string.hasPrefix("q"), string.hasSuffix("_"), string.count > 2,
        let encodedIndex = Int(string.dropFirst().dropLast())
    else {
        return nil
    }
    return encodedIndex + 2
}

private func resolveRelativeDirectPointer(
    at field: UnsafeRawPointer
) -> UnsafeRawPointer {
    field + Int(field.load(as: Int32.self))
}

private func resolveRelativeIndirectablePointer(
    at field: UnsafeRawPointer
) -> UnsafeRawPointer {
    let raw = field.load(as: Int32.self)
    let target = field + Int(raw & ~1)
    return raw & 1 == 0 ? target : target.load(as: UnsafeRawPointer.self)
}
