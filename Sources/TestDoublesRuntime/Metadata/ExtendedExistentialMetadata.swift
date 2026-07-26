import Echo

/// The exact ordinary and extended existential metadata subset supported by
/// runtime stubs.
package struct StubProtocolMetadata {
    package struct AssociatedTypeBinding {
        package let protocolDescriptor: ProtocolDescriptor
        package let name: String
        package let type: Any.Type

        package init(
            protocolDescriptor: ProtocolDescriptor,
            name: String,
            type: Any.Type
        ) {
            self.protocolDescriptor = protocolDescriptor
            self.name = name
            self.type = type
        }

        package init(
            protocolDescriptor: RuntimeProtocolDescriptor,
            name: String,
            type: Any.Type
        ) {
            self.init(
                protocolDescriptor: protocolDescriptor.raw,
                name: name,
                type: type
            )
        }
    }
    package let protocols: [ProtocolDescriptor]
    package let numberOfWitnessTables: Int
    /// Whether the existential includes a protocol that uses a dispatch ABI
    /// other than Swift witness tables, such as an Objective-C protocol.
    package let hasProtocolWithoutSwiftWitnessTable: Bool
    package let isClassConstrained: Bool
    package let hasSuperclassConstraint: Bool
    package let superclass: Any.Type?
    package let specialProtocol: SpecialProtocol
    /// Concrete metadata arguments supplied by an accepted extended
    /// existential shape, keyed by the descriptor and associated-type name
    /// encoded in each same-type requirement.
    package let associatedTypeBindings: [AssociatedTypeBinding]
}

/// Whether an accepted extended existential shape is copied through the
/// value witnesses the Swift runtime instantiates on demand, instead of one
/// of the fixed tables it pre-builds for small witness-table counts.
///
/// The runtime pre-builds opaque-existential tables for zero and one witness
/// tables and class-existential tables for up to two.
package func extendedExistentialUsesRuntimeInstantiatedValueWitnesses(
    isClassConstrained: Bool,
    numberOfWitnessTables: Int
) -> Bool {
    numberOfWitnessTables >= (isClassConstrained ? 3 : 2)
}

/// Whether this process's Swift runtime copies extended existential
/// containers correctly through its runtime-instantiated value witnesses.
///
/// Runtimes that shipped before the 26.4 OS releases read the witness-table
/// count of an extended existential through the ordinary-existential flags
/// word, which actually stores half of the shape pointer, so every container
/// copy overruns the destination by whatever count those pointer bits encode
/// (swiftlang/swift#85346, rdar://163980446).
package let runtimeCopiesExtendedExistentialContainersCorrectly: Bool = {
    if #available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) {
        return true
    }
    return false
}()

package func inspectStubProtocolMetadata(
    _ type: Any.Type,
    typeDescription: String
) throws -> StubProtocolMetadata {
    let metadata = reflect(type)
    if let existential = metadata as? ExistentialMetadata {
        return StubProtocolMetadata(
            protocols: existential.protocols,
            numberOfWitnessTables: existential.flags.numWitnessTables,
            hasProtocolWithoutSwiftWitnessTable: existential.protocolReferences
                .contains { $0.needsWitnessTable == false },
            isClassConstrained: existential.flags.isClassConstraint,
            hasSuperclassConstraint: existential.flags.hasSuperclassConstraint,
            superclass: existential.superclass,
            specialProtocol: existential.flags.specialProtocol,
            associatedTypeBindings: []
        )
    }
    if let extendedExistential = metadata as? ExtendedExistentialMetadata {
        return try inspectExtendedExistential(
            extendedExistential,
            typeDescription: typeDescription
        )
    }
    throw RuntimeConstructionError.typeIsNotProtocol(typeDescription: typeDescription)
}

private func inspectExtendedExistential(
    _ metadata: ExtendedExistentialMetadata,
    typeDescription: String
) throws -> StubProtocolMetadata {
    let shape = metadata.shape
    let flags = shape.flags
    guard
        flags.bits == 0x1900 || flags.bits == 0x1901,
        let specialKind = flags.specialKind
    else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "This extended existential is outside the supported bound-associated-type metadata shape. Only opaque or class-constrained existentials with concretely bound primary associated types are supported."
        )
    }
    let requirements = shape.requirementRequirements
    let unsupportedSuperclassReason =
        "Superclass-constrained bound associated-type existentials are not supported. Use an AnyObject-constrained protocol when the concrete superclass is not required."
    for requirement in requirements where requirement.flags.bits == 0x02 {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: unsupportedSuperclassReason
        )
    }
    guard let generalizationSignature = shape.generalizationSignature else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "Bound associated-type support requires a metadata-only generalization argument for every concrete primary-associated-type binding."
        )
    }
    let numberOfBindings = Int(generalizationSignature.numParams)
    guard
        numberOfBindings > 0,
        shape.requirementParameterCount == numberOfBindings + 1,
        requirements.isEmpty == false,
        generalizationSignature.numKeyArguments == generalizationSignature.numParams
    else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
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
    for requirement in requirements {
        let requirementFlags = requirement.flags.bits
        // Accepted protocol requirements contribute a key witness argument
        // (0x80). Concrete bindings are plain same-type requirements (0x01).
        // Reject extra/key bits on either kind.
        switch requirementFlags {
            case 0x80:
                protocols.append(requirement.protocol)
            case 0x01:
                // The same-type requirement's Type field (RHS) always mangles
                // as "Qyd__" -- dependent member of generalization parameter
                // depth 1 / index 0 -- for every bound associated type,
                // regardless of how many bindings this existential has or
                // which position this one occupies. This shape is shared and
                // reused across different concrete bindings; the RHS mangling
                // only confirms "this is a recognized primary-associated-type
                // projection", while the actual bound type comes from the
                // generalization argument vector at this requirement's
                // *position* (matched via the LHS Param check just below, not
                // by decoding a distinct depth/index per binding). Confirmed
                // against a live two-binding existential in
                // MultipleAssociatedTypeTests -- both requirements use this
                // exact fixed suffix, not "Qyd__"/"Qyd0_" varying by index.
                guard associatedTypeIdentities.count < numberOfBindings,
                    mangledGenericParameter(
                        at: requirement.paramMangledName
                    ) == associatedTypeIdentities.count,
                    let identity = parseAssociatedTypeReference(
                        at: requirement.mangledTypeName,
                        suffix: [0x51, 0x79, 0x64, 0x5f, 0x5f]
                    )
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: typeDescription,
                        reason: "Concrete associated-type bindings are not in a supported deterministic metadata-argument order."
                    )
                }
                associatedTypeIdentities.append(identity)
            case 0x02:
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: typeDescription,
                    reason: unsupportedSuperclassReason
                )
            default:
                throw RuntimeConstructionError.unsupportedProtocolShape(
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
        shape.requirementCount == protocols.count + numberOfBindings
    else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "Bound associated-type support requires one same-type binding per metadata argument and one witness-table requirement per distinct root protocol."
        )
    }
    if extendedExistentialUsesRuntimeInstantiatedValueWitnesses(
        isClassConstrained: specialKind == .class,
        numberOfWitnessTables: protocols.count
    ),
        runtimeCopiesExtendedExistentialContainersCorrectly == false
    {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "The Swift runtime in this process miscounts witness tables while copying bound existential compositions, so materializing one would overrun memory "
                + "(fixed in the 26.4 OS releases by swiftlang/swift#85346). Run on an OS at 26.4 or newer, or stub the unbound composition and supply `associatedTypes:` bindings instead."
        )
    }
    // TargetExtendedExistentialTypeMetadata is kind, shape, then the
    // generalization argument vector. `NumKeyArguments == NumParams` proves
    // Echo's raw argument words contain metadata only, even when trailing
    // generalization requirements describe non-key Copyable constraints.
    // Those trailing requirements are deliberately not interpreted here.
    let generalizationArguments = metadata.generalizationArguments
    guard generalizationArguments.count == numberOfBindings else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: typeDescription,
            reason: "Bound associated-type support requires a metadata-only generalization argument for every concrete primary-associated-type binding."
        )
    }
    let associatedTypeBindings = associatedTypeIdentities.enumerated().map {
        index, identity in
        return StubProtocolMetadata.AssociatedTypeBinding(
            protocolDescriptor: identity.protocolDescriptor,
            name: identity.name,
            type: unsafeBitCast(generalizationArguments[index], to: Any.Type.self)
        )
    }
    return StubProtocolMetadata(
        protocols: protocols,
        numberOfWitnessTables: protocols.count,
        hasProtocolWithoutSwiftWitnessTable: false,
        isClassConstrained: specialKind == .class,
        hasSuperclassConstraint: false,
        superclass: nil,
        specialProtocol: .none,
        associatedTypeBindings: associatedTypeBindings
    )
}

/// Returns the associated-type identity encoded by the supported dependent
/// member mangling used in a protocol requirement signature.
package func parseProtocolAssociatedTypeReference(
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
