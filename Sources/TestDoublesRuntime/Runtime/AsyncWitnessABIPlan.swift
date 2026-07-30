import CTestDoublesTrampoline
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

/// The bounded outgoing async forwarding stack shape, proven against Swift 6.3.
///
/// The target witness transfers `outgoingStackByteCount` to its own
/// continuation stack before resuming the helper, so the completion
/// adjustment is always zero -- the helper must not remove that area twice.
package struct AsyncForwardingStackPlan: Equatable, Sendable {
    package static let maximumVisibleStackWordCount = Int(
        TD_ASYNC_WITNESS_MAX_VISIBLE_STACK_WORDS
    )

    package let visibleArgumentLocations: [CallFrameArgumentLocation]
    package let outgoingStackByteCount: Int
    package let completionStackAdjustmentByteCount: Int

    package init(
        visibleArgumentLocations: [CallFrameArgumentLocation],
        outgoingStackByteCount: Int,
        completionStackAdjustmentByteCount: Int
    ) {
        self.visibleArgumentLocations = visibleArgumentLocations
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
            locations -> (WitnessArgumentDescriptor, [CallFrameArgumentLocation])? in
            let stackLocations = locations.filter {
                if case .stack = $0.storage { return true }
                return false
            }
            guard stackLocations.isEmpty == false else { return nil }
            return (argument, locations)
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
    guard
        stackArguments.lazy.filter({
            isNarrowIntegerAsyncStackValue($0.0)
        }).count <= 1
    else {
        return unsupportedAsyncStubIngressDiagnostic(
            architecture: architecture
        )
    }
    var expectedStackOffset = 0
    for (argument, locations) in stackArguments {
        if let byteCount =
            supportedCompleteTwoWordIntegerAsyncStackValueByteCount(argument)
        {
            guard
                completeTwoWordIntegerStackLocations(
                    locations,
                    valueByteCount: byteCount,
                    expectedStackOffset: expectedStackOffset
                )
            else {
                return unsupportedAsyncStubIngressDiagnostic(
                    architecture: architecture
                )
            }
            expectedStackOffset += 2 * wordByteCount
            continue
        }

        let stackLocations = locations.filter {
            if case .stack = $0.storage { return true }
            return false
        }
        let independentValueByteCount =
            supportedIndependentAsyncStackValueByteCount(argument)
        let isProvenSingleDependentIndirectWord =
            transport.decodedStackByteCount == wordByteCount
            && stackArguments.count == 1
            && locations.count == 1
            && argument.value.dependency.isAssociatedTypeDependent
            && {
                if case .indirect = argument.value.layout {
                    return true
                }
                return false
            }()
        let expectedValueByteCount =
            independentValueByteCount
            ?? (isProvenSingleDependentIndirectWord ? wordByteCount : nil)
        guard
            let expectedValueByteCount,
            locations.count == 1,
            stackLocations.count == 1,
            let location = stackLocations.first,
            case .stack(let byteOffset) = location.storage,
            byteOffset == expectedStackOffset,
            location.valueOffset == 0,
            location.byteCount == expectedValueByteCount
        else {
            return unsupportedAsyncStubIngressDiagnostic(
                architecture: architecture
            )
        }
        expectedStackOffset += asyncStackSlotByteCount(
            forValueByteCount: expectedValueByteCount
        )
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
        + "independent one- or two-word integer, Float, Double, or 16-byte "
        + "single-register SIMD arguments "
        + "supported by the async Stub trampoline. A second narrow integer, "
        + "split or wider integer, smaller floating-point, wider-vector, indirect, "
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
/// This deliberately accepts at most eight stack words contributed by complete
/// concrete one- or two-word integer, `Float`, `Double`, or one-register
/// concrete SIMD values that spill consecutively from their register banks. A
/// second narrow integer, split or wider integer value, smaller floating-point
/// value, indirect value, dependent value, wider-vector value, accessor, and
/// typed-error shape remain fail-closed. A narrow integer still contributes its
/// complete eight-byte ABI stack slot.
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

    let wordByteCount = MemoryLayout<UInt>.size
    var visibleArgumentLocations: [CallFrameArgumentLocation] = []
    var expectedStackOffset = 0
    var narrowIntegerCount = 0
    for (argumentIndex, locations) in transport.argumentLocations.enumerated() {
        let stackLocations = locations.filter {
            if case .stack = $0.storage { return true }
            return false
        }
        guard stackLocations.isEmpty == false else { continue }
        let argument = method.arguments[argumentIndex]
        if isNarrowIntegerAsyncStackValue(argument) {
            narrowIntegerCount += 1
            guard narrowIntegerCount <= 1 else { return nil }
        }
        let consumedStackByteCount: Int
        if let byteCount =
            supportedCompleteTwoWordIntegerAsyncStackValueByteCount(argument)
        {
            guard
                completeTwoWordIntegerStackLocations(
                    locations,
                    valueByteCount: byteCount,
                    expectedStackOffset: expectedStackOffset
                )
            else {
                return nil
            }
            visibleArgumentLocations.append(contentsOf: locations)
            consumedStackByteCount = 2 * wordByteCount
        } else {
            let expectedValueByteCount =
                supportedIndependentAsyncStackValueByteCount(argument)
            guard locations.count == 1,
                stackLocations.count == 1,
                let location = stackLocations.first,
                let expectedValueByteCount,
                case .stack(let byteOffset) = location.storage,
                byteOffset == expectedStackOffset,
                location.valueOffset == 0,
                location.byteCount == expectedValueByteCount
            else {
                return nil
            }
            visibleArgumentLocations.append(
                contentsOf: asyncForwardingWordLocations(for: location)
            )
            consumedStackByteCount = asyncStackSlotByteCount(
                forValueByteCount: expectedValueByteCount
            )
        }
        guard
            visibleArgumentLocations.count
                <= AsyncForwardingStackPlan.maximumVisibleStackWordCount
        else {
            return nil
        }
        expectedStackOffset += consumedStackByteCount
    }

    guard visibleArgumentLocations.isEmpty == false,
        expectedStackOffset == transport.decodedStackByteCount
    else {
        return nil
    }
    let witnessPlan = asyncWitnessStackPlan(
        transport: transport,
        architecture: architecture
    )
    guard witnessPlan.decodedStackByteCount == expectedStackOffset,
        witnessPlan.hiddenStackByteCount == 2 * wordByteCount
    else {
        return nil
    }

    let visibleWordCount = visibleArgumentLocations.count
    switch architecture {
        case .arm64:
            let expectedByteCount =
                visibleWordCount.isMultiple(of: 2)
                ? (visibleWordCount + 2) * wordByteCount
                : (visibleWordCount + 3) * wordByteCount
            guard witnessPlan.stackAdjustmentByteCount == expectedByteCount
            else {
                return nil
            }
        case .x86_64:
            let expectedByteCount =
                (visibleWordCount + 2) / 2 * 2 * wordByteCount
            guard witnessPlan.stackAdjustmentByteCount == expectedByteCount
            else {
                return nil
            }
    }
    return AsyncForwardingStackPlan(
        visibleArgumentLocations: visibleArgumentLocations,
        outgoingStackByteCount: witnessPlan.stackAdjustmentByteCount,
        completionStackAdjustmentByteCount: 0
    )
}

package func unsupportedAsyncForwardingEgressDiagnostic(
    architecture: RuntimeArchitecture
) -> String {
    "Its target-stack egress on \(architecture) is not one through eight "
        + "complete stack words contributed by independent one- or two-word integer, "
        + "Float, Double, or one-register concrete SIMD "
        + "arguments followed by "
        + "dynamic-Self metadata and its witness table. A second narrow "
        + "integer, split or wider integer, smaller floating-point, wider-vector, "
        + "indirect, dependent, accessor, static, and "
        + "typed-error shapes remain unsupported. Use compatible values or a "
        + "hand-written test double."
}

private func supportedIndependentAsyncStackValueByteCount(
    _ argument: WitnessArgumentDescriptor
) -> Int? {
    guard argument.value.dependency.isAssociatedTypeDependent == false
    else { return nil }
    let byteCount = ValueLayoutInfo(reflecting: argument.value.type).size
    switch argument.value.layout {
        case .integer(words: 1)
        where byteCount > 0
            && byteCount <= MemoryLayout<UInt>.size:
            return byteCount
        case .floatingPoint
        where byteCount == MemoryLayout<Float>.size
            || byteCount == MemoryLayout<Double>.size:
            return byteCount
        case .aggregate(let parts)
        where byteCount == 2 * MemoryLayout<UInt>.size
            && concreteSIMDRegisterByteCount(for: argument.value.type)
                == byteCount
            && parts.count == 1
            && parts[0].register == .fp
            && parts[0].offset == 0
            && parts[0].byteCount == byteCount:
            return byteCount
        default:
            return nil
    }
}

private func isNarrowIntegerAsyncStackValue(
    _ argument: WitnessArgumentDescriptor
) -> Bool {
    guard argument.value.dependency.isAssociatedTypeDependent == false,
        case .integer(words: 1) = argument.value.layout
    else {
        return false
    }
    let byteCount = ValueLayoutInfo(reflecting: argument.value.type).size
    return byteCount > 0 && byteCount < MemoryLayout<UInt>.size
}

private func supportedCompleteTwoWordIntegerAsyncStackValueByteCount(
    _ argument: WitnessArgumentDescriptor
) -> Int? {
    guard argument.value.dependency.isAssociatedTypeDependent == false,
        case .integer(words: 2) = argument.value.layout
    else {
        return nil
    }
    let wordByteCount = MemoryLayout<UInt>.size
    let byteCount = ValueLayoutInfo(reflecting: argument.value.type).size
    guard byteCount > wordByteCount,
        byteCount <= 2 * wordByteCount
    else {
        return nil
    }
    return byteCount
}

private func completeTwoWordIntegerStackLocations(
    _ locations: [CallFrameArgumentLocation],
    valueByteCount: Int,
    expectedStackOffset: Int
) -> Bool {
    let wordByteCount = MemoryLayout<UInt>.size
    guard locations.count == 2 else { return false }
    for (index, location) in locations.enumerated() {
        let valueOffset = index * wordByteCount
        guard
            case .stack(let byteOffset) = location.storage,
            byteOffset == expectedStackOffset + valueOffset,
            location.valueOffset == valueOffset,
            location.byteCount
                == min(wordByteCount, valueByteCount - valueOffset)
        else {
            return false
        }
    }
    return true
}

private func asyncStackSlotByteCount(
    forValueByteCount byteCount: Int
) -> Int {
    let wordByteCount = MemoryLayout<UInt>.size
    return max(
        wordByteCount,
        (byteCount + wordByteCount - 1) / wordByteCount * wordByteCount
    )
}

private func asyncForwardingWordLocations(
    for location: CallFrameArgumentLocation
) -> [CallFrameArgumentLocation] {
    guard location.byteCount > MemoryLayout<UInt>.size else {
        return [location]
    }
    guard case .stack(let byteOffset) = location.storage,
        location.byteCount == 2 * MemoryLayout<UInt>.size
    else {
        preconditionFailure(
            "[TestDoubles] An async forwarding stack value is not word-addressable."
        )
    }
    return (0 ..< 2).map { word in
        let wordOffset = word * MemoryLayout<UInt>.size
        return CallFrameArgumentLocation(
            storage: .stack(byteOffset: byteOffset + wordOffset),
            valueOffset: location.valueOffset + wordOffset,
            byteCount: MemoryLayout<UInt>.size
        )
    }
}
