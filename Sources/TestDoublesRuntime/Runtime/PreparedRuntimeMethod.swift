import CTestDoublesTrampoline
import Foundation
import InternalRuntimeContract

/// Construction-time and calibrated ABI plans for one fabricated witness
/// requirement.
///
/// Runtime metadata cannot distinguish a frozen direct-sized struct from a
/// non-frozen struct imported from a library-evolution module. Such methods
/// publish one complete argument-layout vector atomically after the recording
/// call proves it from matcher placeholder bytes.
package final class PreparedRuntimeMethod: @unchecked Sendable {
    private struct CoroutinePlans: Sendable {
        let consuming: RuntimeArgumentDecodingPlan
        let borrowed: RuntimeArgumentDecodingPlan
        let dynamicSelfHiddenArgumentIndex: Int?
    }

    private struct Plans: Sendable {
        let argumentLayouts: [ABIClass]
        let consuming: RuntimeArgumentDecodingPlan
        let borrowed: RuntimeArgumentDecodingPlan
        let coroutinePlans: [Int: CoroutinePlans]
        let asyncStackAdjustmentByteCount: Int?
    }

    package let descriptor: MethodDescriptor
    package let resultTransport: RuntimeResultTransportPlan

    private let lock = NSLock()
    private let argumentLayoutCandidates: [[ABIClass]]
    private var plans: Plans?

    package init(_ descriptor: MethodDescriptor) {
        self.descriptor = descriptor
        argumentLayoutCandidates = descriptor.arguments.map { argument in
            if case .concrete = argument.value.convention {
                return argumentABIClassCandidates(for: argument.value.type)
            }
            return [argument.value.layout]
        }
        resultTransport = RuntimeResultTransportPlan(
            resultType: descriptor.returnType
        )

        let layouts = argumentLayoutCandidates.compactMap { candidates in
            candidates.count == 1 ? candidates[0] : nil
        }
        plans =
            layouts.count == argumentLayoutCandidates.count
            ? Self.makePlans(for: descriptor, argumentLayouts: layouts)
            : nil
    }

    package var asyncStackAdjustmentByteCount: Int? {
        resolvedPlans().asyncStackAdjustmentByteCount
    }

    package var argumentLayouts: [ABIClass] {
        resolvedPlans().argumentLayouts
    }

    package func decodingPlan(
        consumeOwnedArguments: Bool
    ) -> RuntimeArgumentDecodingPlan {
        let plans = resolvedPlans()
        return consumeOwnedArguments ? plans.consuming : plans.borrowed
    }

    package func coroutineDecodingPlan(
        initialGeneralPurposeOffset: Int,
        consumeOwnedArguments: Bool
    ) -> RuntimeArgumentDecodingPlan {
        let plans = resolvedPlans()
        guard let coroutine = plans.coroutinePlans[initialGeneralPurposeOffset]
        else {
            preconditionFailure(
                "[TestDoubles] Unsupported coroutine argument offset \(initialGeneralPurposeOffset)."
            )
        }
        return consumeOwnedArguments ? coroutine.consuming : coroutine.borrowed
    }

    package func coroutineDynamicSelfHiddenArgumentIndex(
        initialGeneralPurposeOffset: Int
    ) -> Int {
        let plans = resolvedPlans()
        guard let coroutine = plans.coroutinePlans[initialGeneralPurposeOffset],
            let index = coroutine.dynamicSelfHiddenArgumentIndex
        else {
            preconditionFailure(
                "[TestDoubles] Calibrated coroutine forwarding for \(descriptor.name) exceeded its hidden-argument transport boundary."
            )
        }
        return index
    }

    /// Resolves every ambiguous argument as one transport vector before any
    /// value witness operation can observe incorrectly reconstructed bytes.
    package func calibrateArgumentLayouts(
        using calibrations: [RuntimeArgumentCalibration],
        from frame: TrampolineCallFrame,
        initialGeneralPurposeOffset: Int? = nil
    ) {
        lock.lock()
        let alreadyResolved = plans != nil
        lock.unlock()
        if alreadyResolved { return }

        guard calibrations.count == descriptor.arguments.count else {
            fatalError(
                "[TestDoubles] Cannot determine the resilient argument convention for "
                    + "\(descriptor.name). Record the call with one Match expression "
                    + "for every argument so the runtime can calibrate it safely."
            )
        }

        let matches = candidateMatches(
            calibrations: calibrations,
            frame: frame,
            initialGeneralPurposeOffset: initialGeneralPurposeOffset
        )
        let strongestEvidence = matches.map(\.indirectEvidence).max()
        // An exact pointee match is positive evidence for indirect transport.
        // Direct registers may still contain stale construction bytes, so when
        // both layouts match, prefer the vector with more such pointer proofs.
        let strongestMatches = matches.filter {
            $0.indirectEvidence == strongestEvidence
        }
        guard strongestMatches.count == 1,
            let selected = strongestMatches.first?.layouts
        else {
            let reason = matches.isEmpty ? "no layout matched" : "multiple layouts matched"
            fatalError(
                "[TestDoubles] Cannot determine the resilient argument convention for "
                    + "\(descriptor.name): \(reason) the recording placeholders. "
                    + "The invocation was rejected before typed argument decoding."
            )
        }

        let selectedPlans = Self.makePlans(
            for: descriptor,
            argumentLayouts: selected
        )
        lock.lock()
        defer { lock.unlock() }
        if let plans {
            precondition(
                plans.argumentLayouts == selected,
                "[TestDoubles] Concurrent ABI calibration selected inconsistent argument layouts."
            )
        } else {
            plans = selectedPlans
        }
    }

    private func resolvedPlans() -> Plans {
        lock.lock()
        defer { lock.unlock() }
        guard let plans else {
            fatalError(
                "[TestDoubles] The resilient argument convention for \(descriptor.name) "
                    + "has not been calibrated. Configure or verify the method with Match "
                    + "expressions before invoking it."
            )
        }
        return plans
    }

    private static func makePlans(
        for descriptor: MethodDescriptor,
        argumentLayouts: [ABIClass]
    ) -> Plans {
        let transport = WitnessCallTransportPlan(
            method: descriptor,
            argumentLayouts: argumentLayouts
        )
        return Plans(
            argumentLayouts: argumentLayouts,
            consuming: RuntimeArgumentDecodingPlan.witness(
                method: descriptor,
                transport: transport,
                argumentLayouts: argumentLayouts,
                consumeOwnedArguments: true
            ),
            borrowed: RuntimeArgumentDecodingPlan.witness(
                method: descriptor,
                transport: transport,
                argumentLayouts: argumentLayouts,
                consumeOwnedArguments: false
            ),
            coroutinePlans: Dictionary(
                uniqueKeysWithValues: [1, 2].map { offset in
                    let coroutineTransport = WitnessCallTransportPlan(
                        method: descriptor,
                        argumentLayouts: argumentLayouts,
                        initialGeneralPurposeOffset: offset,
                        trailingPayload: .dynamicSelf
                    )
                    return (
                        offset,
                        CoroutinePlans(
                            consuming: RuntimeArgumentDecodingPlan.witness(
                                method: descriptor,
                                transport: coroutineTransport,
                                argumentLayouts: argumentLayouts,
                                consumeOwnedArguments: true
                            ),
                            borrowed: RuntimeArgumentDecodingPlan.witness(
                                method: descriptor,
                                transport: coroutineTransport,
                                argumentLayouts: argumentLayouts,
                                consumeOwnedArguments: false
                            ),
                            dynamicSelfHiddenArgumentIndex:
                                coroutineTransport
                                .directForwardingHiddenArgumentIndex
                        )
                    )
                }
            ),
            asyncStackAdjustmentByteCount:
                descriptor.isAsync
                ? asyncWitnessStackPlan(
                    for: descriptor,
                    argumentLayouts: argumentLayouts,
                    architecture: .current
                ).stackAdjustmentByteCount
                : nil
        )
    }

    private func candidateMatches(
        calibrations: [RuntimeArgumentCalibration],
        frame: TrampolineCallFrame,
        initialGeneralPurposeOffset: Int?
    ) -> [(layouts: [ABIClass], indirectEvidence: Int)] {
        let maximumLiveCandidateCount = 256
        var matches: [(layouts: [ABIClass], indirectEvidence: Int)] = [([], 0)]
        for index in descriptor.arguments.indices {
            let argument = descriptor.arguments[index]
            let calibration = calibrations[index]
            guard
                let calibrationBytes = calibration.bytes(for: argument.value.type)
            else {
                return []
            }
            let candidates = argumentLayoutCandidates[index]
            matches = matches.flatMap { match in
                candidates.compactMap { layout in
                    let layouts = match.layouts + [layout]
                    guard
                        calibrationMatches(
                            calibrationBytes,
                            layout: layout,
                            comparisonLayout: candidates[0],
                            locations: argumentLocations(
                                for: layouts,
                                initialGeneralPurposeOffset:
                                    initialGeneralPurposeOffset
                            ),
                            frame: frame
                        )
                    else {
                        return nil
                    }
                    return (
                        layouts: layouts,
                        indirectEvidence:
                            match.indirectEvidence
                            + (layout == .indirect && candidates.count > 1 ? 1 : 0)
                    )
                }
            }
            guard matches.count <= maximumLiveCandidateCount else {
                fatalError(
                    "[TestDoubles] \(descriptor.name) has too many indistinguishable "
                        + "resilient argument layouts to calibrate safely."
                )
            }
        }
        return matches
    }

    private func argumentLocations(
        for layouts: [ABIClass],
        initialGeneralPurposeOffset: Int?
    ) -> [CallFrameArgumentLocation] {
        let initialGeneralPurposeOffset =
            initialGeneralPurposeOffset
            ?? (descriptor.isAsync && descriptor.returnLayout == .indirect ? 1 : 0)
        let plan = CallFrameArgumentLocationPlan(
            arguments: zip(descriptor.arguments, layouts).map { argument, layout in
                CallFrameArgumentShape(type: argument.value.type, layout: layout)
            },
            initialGeneralPurposeOffset: initialGeneralPurposeOffset
        )
        return plan.arguments.last ?? []
    }

    private func calibrationMatches(
        _ calibrationBytes: [UInt8],
        layout: ABIClass,
        comparisonLayout: ABIClass,
        locations: [CallFrameArgumentLocation],
        frame: TrampolineCallFrame
    ) -> Bool {
        let byteCount = calibrationBytes.count
        var observed = [UInt8](repeating: 0, count: byteCount)
        let copied: Bool
        switch layout {
            case .indirect:
                guard locations.count == 1,
                    let source = UnsafeRawPointer(
                        bitPattern: UInt(frame.scalarBits(at: locations[0]))
                    )
                else {
                    return false
                }
                copied = observed.withUnsafeMutableBytes { destination in
                    td_read_process_memory(
                        source,
                        destination.baseAddress,
                        byteCount
                    )
                }
            default:
                copied = observed.withUnsafeMutableBytes { destination in
                    guard let base = destination.baseAddress else {
                        return byteCount == 0
                    }
                    for location in locations {
                        guard location.valueOffset + location.byteCount <= byteCount else {
                            return false
                        }
                        frame.copyArgumentBytes(
                            at: location,
                            into: base + location.valueOffset
                        )
                    }
                    return true
                }
        }
        guard copied else { return false }

        let ranges = meaningfulRanges(
            for: comparisonLayout,
            byteCount: byteCount
        )
        return ranges.allSatisfy { range in
            observed[range] == calibrationBytes[range]
        }
    }

    private func meaningfulRanges(
        for layout: ABIClass,
        byteCount: Int
    ) -> [Range<Int>] {
        switch layout {
            case .void:
                return []
            case .floatingPoint, .integer:
                return [0 ..< byteCount]
            case .aggregate(let parts):
                return parts.compactMap { part in
                    let end = min(part.offset + part.byteCount, byteCount)
                    return part.offset < end ? part.offset ..< end : nil
                }
            case .indirect:
                return [0 ..< byteCount]
        }
    }
}
