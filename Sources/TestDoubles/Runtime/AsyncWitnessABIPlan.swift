import Echo

struct AsyncWitnessStackPlan: Equatable, Sendable {
    let decodedStackByteCount: Int
    let hiddenStackByteCount: Int
    let stackAdjustmentByteCount: Int
}

/// The one outgoing async Spy stack shape proven against Swift 6.3.
///
/// `visibleArgumentLocation` identifies the word that must be copied while the
/// outer witness-entry frame is still live. `outgoingStackByteCount` is the
/// area the forwarding helper creates before entering the real target witness.
/// The target witness transfers that area to its compiler-selected
/// continuation stack before resuming the helper. The completion adjustment is
/// therefore zero for every supported architecture and records that the helper
/// must not remove the area a second time.
struct AsyncForwardingStackPlan: Equatable, Sendable {
    let visibleArgumentLocation: CallFrameArgumentLocation
    let outgoingStackByteCount: Int
    let completionStackAdjustmentByteCount: Int
}

func unsupportedRuntimeReason(
    for method: MethodDescriptor,
    architecture: RuntimeArchitecture
) -> String? {
    guard method.isAsync else { return nil }

    let stackPlan = asyncWitnessStackPlan(
        for: method,
        architecture: architecture
    )
    // `prepareAsync` decodes this ingress plan before it can return a retained
    // state to assembly. The state owns decoded arguments and never follows the
    // snapshot's caller-stack pointer after suspension.
    let supportedStackByteCount = MemoryLayout<UInt>.size

    guard stackPlan.decodedStackByteCount > supportedStackByteCount else {
        return nil
    }
    let requiredStackWords =
        stackPlan.decodedStackByteCount / MemoryLayout<UInt>.size
    return "Its arguments and hidden result or error storage require \(requiredStackWords) incoming "
        + "stack words on \(architecture). The async Stub trampoline supports only the "
        + "first spilled word; wider ingress needs continuation-owned stack transport. "
        + "Use fewer values or a hand-written test double."
}

func asyncWitnessStackPlan(
    for method: MethodDescriptor,
    architecture: RuntimeArchitecture
) -> AsyncWitnessStackPlan {
    precondition(method.isAsync)

    let transport = WitnessCallTransportPlan(
        method: method,
        trailingPayload: .dynamicSelf,
        architecture: architecture
    )
    return asyncWitnessStackPlan(
        transport: transport,
        architecture: architecture
    )
}

private func asyncWitnessStackPlan(
    transport: WitnessCallTransportPlan,
    architecture: RuntimeArchitecture
) -> AsyncWitnessStackPlan {
    let wordByteCount = MemoryLayout<UInt>.size
    let unalignedStackByteCount = transport.stackByteCount
    let stackAlignment = 2 * wordByteCount
    let stackAdjustmentByteCount: Int
    switch architecture {
        case .arm64:
            let (alignmentNumerator, alignmentOverflow) =
                unalignedStackByteCount.addingReportingOverflow(
                    stackAlignment - 1
                )
            precondition(
                alignmentOverflow == false,
                "[TestDoubles] arm64 async witness stack adjustment overflowed."
            )
            stackAdjustmentByteCount =
                unalignedStackByteCount == 0
                ? 0
                : alignmentNumerator / stackAlignment * stackAlignment
            precondition(
                stackAdjustmentByteCount >= unalignedStackByteCount
                    && stackAdjustmentByteCount - unalignedStackByteCount
                        < stackAlignment,
                "[TestDoubles] arm64 async witness stack adjustment did not round up."
            )
        case .x86_64:
            // Swift's x86_64 async witness entry leaves an implicit eight-byte
            // slot below the address captured by `stackPointer`. One logical
            // stack word therefore needs no SP movement; each complete pair
            // advances continuation SP by one 16-byte aligned block.
            stackAdjustmentByteCount =
                unalignedStackByteCount / stackAlignment * stackAlignment
            precondition(
                stackAdjustmentByteCount <= unalignedStackByteCount
                    && unalignedStackByteCount - stackAdjustmentByteCount
                        < stackAlignment,
                "[TestDoubles] x86_64 async witness stack adjustment did not round down."
            )
    }
    precondition(
        stackAdjustmentByteCount % stackAlignment == 0,
        "[TestDoubles] Async witness stack adjustment is not ABI-aligned."
    )
    return AsyncWitnessStackPlan(
        decodedStackByteCount: transport.decodedStackByteCount,
        hiddenStackByteCount: transport.hiddenStackByteCount,
        stackAdjustmentByteCount: stackAdjustmentByteCount
    )
}

/// Returns the bounded outgoing async forwarding stack plan, or `nil` when a
/// requirement needs a different physical shape.
///
/// This deliberately accepts only one complete concrete eight-byte value that
/// spills from the general-purpose bank. Split, padded, indirect, dependent,
/// vector, accessor, and typed-error shapes remain fail-closed.
func asyncForwardingStackPlan(
    for method: MethodDescriptor,
    architecture: RuntimeArchitecture
) -> AsyncForwardingStackPlan? {
    guard method.isAsync,
        method.kind == .method,
        method.receiver == .instance,
        method.isThrowing == false,
        method.typedErrorType == nil
    else {
        return nil
    }

    let transport = WitnessCallTransportPlan(
        method: method,
        trailingPayload: .dynamicSelf,
        architecture: architecture
    )

    var spilledArgumentIndex: Int?
    var visibleArgumentLocation: CallFrameArgumentLocation?
    for (argumentIndex, locations) in transport.argumentLocations.enumerated() {
        for location in locations {
            guard case .stack = location.storage else { continue }
            guard visibleArgumentLocation == nil else { return nil }
            spilledArgumentIndex = argumentIndex
            visibleArgumentLocation = location
        }
    }
    guard let spilledArgumentIndex,
        let visibleArgumentLocation,
        transport.decodedStackByteCount == MemoryLayout<UInt>.size,
        transport.argumentLocations[spilledArgumentIndex].count == 1,
        visibleArgumentLocation.storage == .stack(byteOffset: 0),
        visibleArgumentLocation.valueOffset == 0,
        visibleArgumentLocation.byteCount == MemoryLayout<UInt>.size,
        method.arguments[spilledArgumentIndex].value.dependency
            .isAssociatedTypeDependent == false,
        reflect(method.arguments[spilledArgumentIndex].value.type).vwt.size
            == MemoryLayout<UInt>.size,
        case .integer(words: 1) =
            method.arguments[spilledArgumentIndex].value.layout
    else {
        return nil
    }

    let witnessPlan = asyncWitnessStackPlan(
        transport: transport,
        architecture: architecture
    )
    guard witnessPlan.decodedStackByteCount == MemoryLayout<UInt>.size,
        witnessPlan.hiddenStackByteCount == 2 * MemoryLayout<UInt>.size
    else {
        return nil
    }

    switch architecture {
        case .arm64:
            guard witnessPlan.stackAdjustmentByteCount == 32 else { return nil }
        case .x86_64:
            guard witnessPlan.stackAdjustmentByteCount == 16 else { return nil }
    }
    return AsyncForwardingStackPlan(
        visibleArgumentLocation: visibleArgumentLocation,
        outgoingStackByteCount: witnessPlan.stackAdjustmentByteCount,
        completionStackAdjustmentByteCount: 0
    )
}
