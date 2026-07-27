import EchoRuntimeReflection
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport

package struct AsyncWitnessStackPlan: Equatable, Sendable {
    package let decodedStackByteCount: Int
    package let hiddenStackByteCount: Int
    package let stackAdjustmentByteCount: Int

    package init(
        decodedStackByteCount: Int,
        hiddenStackByteCount: Int,
        stackAdjustmentByteCount: Int
    ) {
        self.decodedStackByteCount = decodedStackByteCount
        self.hiddenStackByteCount = hiddenStackByteCount
        self.stackAdjustmentByteCount = stackAdjustmentByteCount
    }
}

/// The one outgoing async forwarding stack shape proven against Swift 6.3.
///
/// `visibleArgumentLocation` identifies the word that must be copied while the
/// outer witness-entry frame is still live. `outgoingStackByteCount` is the
/// area the forwarding helper creates before entering the real target witness.
/// The target witness transfers that area to its compiler-selected
/// continuation stack before resuming the helper. The completion adjustment is
/// therefore zero for every supported architecture and records that the helper
/// must not remove the area a second time.
package struct AsyncForwardingStackPlan: Equatable, Sendable {
    package let visibleArgumentLocation: CallFrameArgumentLocation
    package let outgoingStackByteCount: Int
    package let completionStackAdjustmentByteCount: Int

    package init(
        visibleArgumentLocation: CallFrameArgumentLocation,
        outgoingStackByteCount: Int,
        completionStackAdjustmentByteCount: Int
    ) {
        self.visibleArgumentLocation = visibleArgumentLocation
        self.outgoingStackByteCount = outgoingStackByteCount
        self.completionStackAdjustmentByteCount = completionStackAdjustmentByteCount
    }
}

package func unsupportedRuntimeReason(
    for method: MethodDescriptor,
    architecture: RuntimeArchitecture
) -> String? {
    guard method.isAsync else { return nil }

    let transport = WitnessCallTransportPlan(
        method: method,
        trailingPayload: .dynamicSelf,
        architecture: architecture
    )
    let stackPlan = asyncWitnessStackPlan(
        transport: transport,
        architecture: architecture
    )
    // `prepareAsync` decodes this ingress plan before it can return a retained
    // state to assembly. The state owns decoded arguments and never follows the
    // snapshot's caller-stack pointer after suspension.
    guard stackPlan.decodedStackByteCount > 0 else {
        return nil
    }
    return unsupportedAsyncStubIngressReason(
        for: method,
        transport: transport,
        architecture: architecture
    )
}

private func unsupportedAsyncStubIngressReason(
    for method: MethodDescriptor,
    transport: WitnessCallTransportPlan,
    architecture: RuntimeArchitecture
) -> String? {
    let wordByteCount = MemoryLayout<UInt>.size
    let stackArguments = zip(method.arguments, transport.argumentLocations)
        .compactMap {
            argument,
            locations -> (WitnessArgumentDescriptor, CallFrameArgumentLocation)? in
            let stackLocations = locations.filter {
                if case .stack = $0.storage { return true }
                return false
            }
            guard stackLocations.isEmpty == false else { return nil }
            guard locations.count == 1, let location = stackLocations.first else {
                return (argument, stackLocations[0])
            }
            return (argument, location)
        }

    if let typedErrorDestination = transport.typedErrorDestinationLocation,
        case .stack = typedErrorDestination.storage
    {
        guard method.kind == .method,
            stackArguments.isEmpty,
            transport.decodedStackByteCount == wordByteCount
        else {
            return unsupportedAsyncStubIngressDiagnostic(
                architecture: architecture
            )
        }
        return nil
    }

    guard method.kind == .method else {
        return unsupportedAsyncStubIngressDiagnostic(
            architecture: architecture
        )
    }
    var expectedStackOffset = 0
    for (argument, location) in stackArguments {
        let isCompleteIndependentWord =
            argument.value.dependency.isAssociatedTypeDependent == false
            && {
                if case .integer(words: 1) = argument.value.layout {
                    return true
                }
                return false
            }()
            && ValueLayoutInfo(reflecting: argument.value.type).size
                == wordByteCount
        let isProvenSingleDependentIndirectWord =
            transport.decodedStackByteCount == wordByteCount
            && stackArguments.count == 1
            && argument.value.dependency.isAssociatedTypeDependent
            && {
                if case .indirect = argument.value.layout {
                    return true
                }
                return false
            }()
        guard
            isCompleteIndependentWord || isProvenSingleDependentIndirectWord,
            case .stack(let byteOffset) = location.storage,
            byteOffset == expectedStackOffset,
            location.valueOffset == 0,
            location.byteCount == wordByteCount
        else {
            return unsupportedAsyncStubIngressDiagnostic(
                architecture: architecture
            )
        }
        expectedStackOffset += wordByteCount
    }
    guard expectedStackOffset == transport.decodedStackByteCount else {
        return unsupportedAsyncStubIngressDiagnostic(
            architecture: architecture
        )
    }

    if transport.decodedStackByteCount > wordByteCount {
        guard method.typedErrorType == nil
        else {
            return unsupportedAsyncStubIngressDiagnostic(
                architecture: architecture
            )
        }
    }
    return nil
}

private func unsupportedAsyncStubIngressDiagnostic(
    architecture: RuntimeArchitecture
) -> String {
    "Its caller-stack ingress on \(architecture) is not a sequence of complete, "
        + "independent eight-byte general-purpose arguments supported by the async "
        + "Stub trampoline. Split, padded, floating-point, vector, indirect, "
        + "dependent, accessor, and wider typed-error shapes remain unsupported. "
        + "Use compatible values or a hand-written test double."
}

package func asyncWitnessStackPlan(
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
package func asyncForwardingStackPlan(
    for method: MethodDescriptor,
    architecture: RuntimeArchitecture
) -> AsyncForwardingStackPlan? {
    guard method.isAsync,
        method.kind == .method,
        method.receiver == .instance,
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
        ValueLayoutInfo(
            reflecting: method.arguments[spilledArgumentIndex].value.type
        ).size
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
