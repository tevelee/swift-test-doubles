import CTestDoublesTrampoline
import Foundation
import InternalRuntimeContract
import TestDoublesRuntimeMetadata

/// Construction-time and calibrated ABI plans for one fabricated witness
/// requirement.
///
/// Runtime metadata cannot distinguish a frozen direct-sized struct from a
/// non-frozen struct imported from a library-evolution module. Such methods
/// publish one complete argument-layout vector atomically after the recording
/// call proves it from matcher placeholder bytes.
package final class PreparedRuntimeMethod: @unchecked Sendable {
    private struct Plans: Sendable {
        let argumentLayouts: [ABIClass]
        let consuming: RuntimeArgumentDecodingPlan
        let borrowed: RuntimeArgumentDecodingPlan
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

    /// Resolves every ambiguous argument as one transport vector before any
    /// value witness operation can observe incorrectly reconstructed bytes.
    package func calibrateArgumentLayouts(
        using calibrations: [RuntimeArgumentCalibration],
        from frame: TrampolineCallFrame
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

        let vectors = candidateVectors()
        let matches = vectors.compactMap { layouts in
            candidateMatches(
                layouts,
                calibrations: calibrations,
                frame: frame
            )
                ? (
                    layouts: layouts,
                    indirectEvidence: zip(layouts, argumentLayoutCandidates)
                        .reduce(into: 0) { count, pair in
                            if pair.0 == .indirect && pair.1.count > 1 {
                                count += 1
                            }
                        }
                ) : nil
        }
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

    private func candidateVectors() -> [[ABIClass]] {
        let maximumCandidateCount = 256
        var vectors: [[ABIClass]] = [[]]
        for candidates in argumentLayoutCandidates {
            guard vectors.count <= maximumCandidateCount / candidates.count else {
                fatalError(
                    "[TestDoubles] \(descriptor.name) has too many ambiguous resilient "
                        + "argument layouts to calibrate safely."
                )
            }
            vectors = vectors.flatMap { prefix in
                candidates.map { prefix + [$0] }
            }
        }
        return vectors
    }

    private func candidateMatches(
        _ layouts: [ABIClass],
        calibrations: [RuntimeArgumentCalibration],
        frame: TrampolineCallFrame
    ) -> Bool {
        let transport = WitnessCallTransportPlan(
            method: descriptor,
            argumentLayouts: layouts
        )
        for index in descriptor.arguments.indices {
            let argument = descriptor.arguments[index]
            let calibration = calibrations[index]
            guard
                ObjectIdentifier(calibration.type)
                    == ObjectIdentifier(argument.value.type),
                calibrationMatches(
                    calibration,
                    layout: layouts[index],
                    comparisonLayout: argumentLayoutCandidates[index][0],
                    locations: transport.argumentLocations[index],
                    frame: frame
                )
            else {
                return false
            }
        }
        return true
    }

    private func calibrationMatches(
        _ calibration: RuntimeArgumentCalibration,
        layout: ABIClass,
        comparisonLayout: ABIClass,
        locations: [CallFrameArgumentLocation],
        frame: TrampolineCallFrame
    ) -> Bool {
        let byteCount = calibration.bytes.count
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
            observed[range] == calibration.bytes[range]
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
