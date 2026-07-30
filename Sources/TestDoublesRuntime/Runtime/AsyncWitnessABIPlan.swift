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
    let stackArguments = asyncSpilledArguments(
        method: method,
        transport: transport
    )

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
        supportedAsyncVisibleStackByteCount(
            stackArguments,
            transport: transport,
            architecture: architecture,
            permitsSingleDependentIndirectWord: true
        ) == transport.decodedStackByteCount
    else {
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
        + "independent one- or two-word integer, Float16, Float, Double, or "
        + "SIMD arguments occupying one through four registers "
        + "supported by the async Stub trampoline. "
        + "split or wider integer, wider-vector, "
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
/// concrete one- or two-word integer, `Float`, `Double`, or concrete SIMD values
/// occupying one through four registers that spill consecutively from their
/// banks. Split or wider integer values, dependent values, wider-vector values,
/// accessors, and typed-error shapes remain fail-closed. A narrow integer,
/// `Float16`, or independent indirect value still contributes its complete
/// eight-byte ABI stack slot.
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
    guard
        let visibleStackByteCount = supportedAsyncVisibleStackByteCount(
            asyncSpilledArguments(method: method, transport: transport),
            transport: transport,
            architecture: architecture,
            permitsSingleDependentIndirectWord: false
        ),
        visibleStackByteCount > 0,
        visibleStackByteCount == transport.decodedStackByteCount
    else {
        return nil
    }
    let visibleWordCount =
        (visibleStackByteCount + wordByteCount - 1) / wordByteCount
    guard
        visibleWordCount
            <= AsyncForwardingStackPlan.maximumVisibleStackWordCount
    else {
        return nil
    }
    let visibleArgumentLocations = (0 ..< visibleWordCount).map {
        CallFrameArgumentLocation(
            storage: .stack(byteOffset: $0 * wordByteCount),
            valueOffset: 0,
            byteCount: wordByteCount
        )
    }
    let witnessPlan = asyncWitnessStackPlan(
        transport: transport,
        architecture: architecture
    )
    let hiddenStart = visibleWordCount * wordByteCount
    guard witnessPlan.decodedStackByteCount == visibleStackByteCount,
        let dynamicSelf = transport.dynamicSelfLocations,
        dynamicSelf.metadata.storage == .stack(byteOffset: hiddenStart),
        dynamicSelf.witnessTable.storage
            == .stack(byteOffset: hiddenStart + wordByteCount)
    else {
        return nil
    }

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
        + "Float16, Float, Double, or concrete SIMD arguments occupying one "
        + "through four registers followed by "
        + "dynamic-Self metadata and its witness table. "
        + "Split or wider integer, wider-vector, "
        + "dependent, accessor, static, and "
        + "typed-error shapes remain unsupported. Use compatible values or a "
        + "hand-written test double."
}

private struct AsyncSpilledArgument {
    let argument: WitnessArgumentDescriptor
    let locations: [CallFrameArgumentLocation]
}

private func asyncSpilledArguments(
    method: MethodDescriptor,
    transport: WitnessCallTransportPlan
) -> [AsyncSpilledArgument] {
    zip(method.arguments, transport.argumentLocations).compactMap {
        argument,
        locations in
        guard
            locations.contains(where: {
                if case .stack = $0.storage { return true }
                return false
            })
        else {
            return nil
        }
        return AsyncSpilledArgument(
            argument: argument,
            locations: locations
        )
    }
}

private func supportedAsyncVisibleStackByteCount(
    _ spilledArguments: [AsyncSpilledArgument],
    transport: WitnessCallTransportPlan,
    architecture: RuntimeArchitecture,
    permitsSingleDependentIndirectWord: Bool
) -> Int? {
    var expectedStackOffset = 0
    for spilled in spilledArguments {
        expectedStackOffset = alignedAsyncStackOffset(
            expectedStackOffset,
            for: spilled.argument,
            architecture: architecture
        )
        guard
            let consumedByteCount = supportedAsyncStackValueConsumedByteCount(
                spilled,
                expectedStackOffset: expectedStackOffset,
                transport: transport,
                spilledArgumentCount: spilledArguments.count,
                architecture: architecture,
                permitsSingleDependentIndirectWord:
                    permitsSingleDependentIndirectWord
            )
        else {
            return nil
        }
        expectedStackOffset += consumedByteCount
    }
    return expectedStackOffset
}

private func supportedAsyncStackValueConsumedByteCount(
    _ spilled: AsyncSpilledArgument,
    expectedStackOffset: Int,
    transport: WitnessCallTransportPlan,
    spilledArgumentCount: Int,
    architecture: RuntimeArchitecture,
    permitsSingleDependentIndirectWord: Bool
) -> Int? {
    let argument = spilled.argument
    let locations = spilled.locations
    if let byteCount =
        supportedCompleteSIMDAsyncStackValueByteCount(argument)
    {
        guard
            completeSIMDStackLocations(
                locations,
                valueByteCount: byteCount,
                expectedStackOffset: expectedStackOffset
            )
        else {
            return nil
        }
        return asyncStackConsumedByteCount(
            byteCount,
            architecture: architecture
        )
    }
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
        return asyncStackConsumedByteCount(
            byteCount,
            architecture: architecture
        )
    }

    let wordByteCount = MemoryLayout<UInt>.size
    let isProvenSingleDependentIndirectWord =
        permitsSingleDependentIndirectWord
        && transport.decodedStackByteCount == wordByteCount
        && spilledArgumentCount == 1
        && locations.count == 1
        && argument.value.dependency.isAssociatedTypeDependent
        && {
            if case .indirect = argument.value.layout { return true }
            return false
        }()
    let expectedValueByteCount =
        supportedIndependentAsyncStackValueByteCount(argument)
        ?? (isProvenSingleDependentIndirectWord ? wordByteCount : nil)
    let stackLocations = locations.filter {
        if case .stack = $0.storage { return true }
        return false
    }
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
        return nil
    }
    return asyncStackConsumedByteCount(
        expectedValueByteCount,
        architecture: architecture
    )
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
            || byteCount == MemoryLayout<Double>.size
            || isFloat16(argument.value.type):
            return byteCount
        case .indirect:
            return MemoryLayout<UInt>.size
        default:
            return nil
    }
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

private func supportedCompleteSIMDAsyncStackValueByteCount(
    _ argument: WitnessArgumentDescriptor
) -> Int? {
    guard argument.value.dependency.isAssociatedTypeDependent == false,
        let byteCount = concreteSIMDRegisterByteCount(
            for: argument.value.type
        ),
        case .aggregate(let parts) = argument.value.layout,
        parts.count == byteCount / 16,
        parts.enumerated().allSatisfy({ index, part in
            part.register == .fp
                && part.offset == index * 16
                && part.byteCount == 16
        })
    else {
        return nil
    }
    return byteCount
}

private func completeSIMDStackLocations(
    _ locations: [CallFrameArgumentLocation],
    valueByteCount: Int,
    expectedStackOffset: Int
) -> Bool {
    let fragmentByteCount = 16
    guard locations.count == valueByteCount / fragmentByteCount
    else {
        return false
    }
    for (index, location) in locations.enumerated() {
        let valueOffset = index * fragmentByteCount
        guard
            case .stack(let byteOffset) = location.storage,
            byteOffset == expectedStackOffset + valueOffset,
            location.valueOffset == valueOffset,
            location.byteCount == fragmentByteCount
        else {
            return false
        }
    }
    return true
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

private func alignedAsyncStackOffset(
    _ offset: Int,
    for argument: WitnessArgumentDescriptor,
    architecture: RuntimeArchitecture
) -> Int {
    guard architecture == .arm64 else { return offset }
    let alignment: Int
    if case .indirect = argument.value.layout {
        alignment = MemoryLayout<UInt>.alignment
    } else {
        alignment =
            ValueLayoutInfo(reflecting: argument.value.type)
            .alignment
    }
    let (numerator, overflow) = offset.addingReportingOverflow(
        alignment - 1
    )
    precondition(
        overflow == false,
        "[TestDoubles] Async stack alignment overflowed."
    )
    return numerator / alignment * alignment
}

private func asyncStackConsumedByteCount(
    _ byteCount: Int,
    architecture: RuntimeArchitecture
) -> Int {
    switch architecture {
        case .arm64:
            return byteCount
        case .x86_64:
            let wordByteCount = MemoryLayout<UInt>.size
            return max(
                wordByteCount,
                (byteCount + wordByteCount - 1) / wordByteCount
                    * wordByteCount
            )
    }
}
