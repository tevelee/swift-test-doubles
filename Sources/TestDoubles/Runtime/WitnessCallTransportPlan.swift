/// The physical call-frame transport for one protocol witness signature.
///
/// This is the single allocation pass for formal arguments and the hidden
/// general-purpose words that follow them. Consumers select the trailing ABI
/// payload they need, but all of them observe the same register banks and
/// declaration-order stack cursor.
struct WitnessCallTransportPlan: Sendable {
    enum TrailingPayload: Sendable {
        case none
        case dynamicSelf
        case typedAdapterInvocation

        fileprivate var generalPurposeWordCount: Int {
            switch self {
                case .none: 0
                case .dynamicSelf: 2
                case .typedAdapterInvocation: 1
            }
        }
    }

    struct DynamicSelfLocations: Equatable, Sendable {
        let metadata: CallFrameArgumentLocation
        let witnessTable: CallFrameArgumentLocation

        var consecutiveRegisterStart: Int? {
            guard case .generalPurposeRegister(let metadataIndex) = metadata.storage,
                case .generalPurposeRegister(let witnessTableIndex) = witnessTable.storage,
                witnessTableIndex == metadataIndex + 1
            else {
                return nil
            }
            return metadataIndex
        }
    }

    let argumentLocations: [[CallFrameArgumentLocation]]
    let asyncIndirectResultLocation: CallFrameArgumentLocation?
    let typedErrorDestinationLocation: CallFrameArgumentLocation?
    let dynamicSelfLocations: DynamicSelfLocations?
    let typedAdapterInvocationLocation: CallFrameArgumentLocation?

    /// Stack bytes copied by argument decoding, including an indirect typed
    /// error destination but excluding dynamic-Self metadata and witness words.
    let decodedStackByteCount: Int

    /// Stack bytes occupied only by the selected trailing payload.
    let hiddenStackByteCount: Int
    let stackByteCount: Int

    init(
        method: MethodDescriptor,
        initialGeneralPurposeOffset: Int = 0,
        trailingPayload: TrailingPayload = .none,
        architecture: RuntimeArchitecture = .current
    ) {
        let hasAsyncIndirectResult: Bool
        if method.isAsync, case .indirect = method.result.layout {
            hasAsyncIndirectResult = true
        } else {
            hasAsyncIndirectResult = false
        }

        if hasAsyncIndirectResult {
            precondition(
                initialGeneralPurposeOffset
                    < architecture.generalPurposeArgumentRegisterCount,
                "[TestDoubles] Async indirect-result storage has no general-purpose register."
            )
            asyncIndirectResultLocation = CallFrameArgumentLocation(
                storage: .generalPurposeRegister(initialGeneralPurposeOffset),
                valueOffset: 0,
                byteCount: MemoryLayout<UInt>.size
            )
        } else {
            asyncIndirectResultLocation = nil
        }

        let typedErrorWordCount = method.typedErrorUsesIndirectResultSlot ? 1 : 0
        let locationPlan = CallFrameArgumentLocationPlan(
            arguments: method.arguments.map {
                CallFrameArgumentShape(
                    type: $0.value.type,
                    layout: $0.value.layout
                )
            },
            initialGeneralPurposeOffset: initialGeneralPurposeOffset
                + (hasAsyncIndirectResult ? 1 : 0),
            trailingGeneralPurposeWordCount: typedErrorWordCount
                + trailingPayload.generalPurposeWordCount,
            architecture: architecture
        )
        argumentLocations = locationPlan.arguments

        var trailing = locationPlan.trailingGeneralPurpose[...]
        if method.typedErrorUsesIndirectResultSlot {
            typedErrorDestinationLocation = trailing.removeFirst()
        } else {
            typedErrorDestinationLocation = nil
        }
        let typedErrorStackByteCount =
            typedErrorDestinationLocation?.isStack == true
            ? MemoryLayout<UInt>.size : 0
        decodedStackByteCount =
            locationPlan.argumentStackByteCount
            + typedErrorStackByteCount

        switch trailingPayload {
            case .none:
                precondition(trailing.isEmpty)
                dynamicSelfLocations = nil
                typedAdapterInvocationLocation = nil

            case .dynamicSelf:
                precondition(trailing.count == 2)
                dynamicSelfLocations = DynamicSelfLocations(
                    metadata: trailing.removeFirst(),
                    witnessTable: trailing.removeFirst()
                )
                typedAdapterInvocationLocation = nil

            case .typedAdapterInvocation:
                precondition(trailing.count == 1)
                dynamicSelfLocations = nil
                typedAdapterInvocationLocation = trailing.removeFirst()
        }
        precondition(trailing.isEmpty)

        stackByteCount = locationPlan.stackByteCount
        hiddenStackByteCount = stackByteCount - decodedStackByteCount
    }

    /// The first register available for target metadata and its witness table
    /// when the complete call stays inside the captured register banks. Used
    /// by `_read`/`_modify` forwarding, whose invoke routines have no outgoing
    /// stack transport at all, so metadata and witness table must both land
    /// in registers or the call is declined.
    var directForwardingHiddenArgumentIndex: Int? {
        guard decodedStackByteCount == 0,
            hiddenStackByteCount == 0
        else {
            return nil
        }
        return dynamicSelfLocations?.consecutiveRegisterStart
    }

    /// One source for an outgoing stack word a forwarding call must copy to
    /// the real target: either a spilled visible argument (read from the
    /// captured incoming frame) or the target's own metadata/witness-table
    /// pointer (computed at forwarding time, never read from the frame).
    enum OutgoingStackSource: Equatable, Sendable {
        case argument(CallFrameArgumentLocation)
        case metadata
        case witnessTable
    }

    /// The maximum number of caller-stack words `td_swift_invoke_witness`
    /// will copy to the outgoing call, as explicit parameters — it never
    /// touches `TDCallFrame`'s layout, so this ceiling is purely a
    /// self-imposed, testable limit, not an ABI constraint.
    static let maximumOutgoingStackWords = 2

    /// The ordered outgoing-stack-word sources for a synchronous forwarding
    /// call whose total (spilled visible arguments plus whichever of
    /// metadata/witness-table the real target's own calling convention also
    /// spills) fits within `maximumOutgoingStackWords`. `nil` when the call
    /// needs more than that, or needs stack transport this method doesn't
    /// model (an indirect typed-error destination that itself spilled).
    ///
    /// Metadata and witness table are **not** reserved a fixed register
    /// pair: the real target witness function's own compiled code expects
    /// them immediately following its visible arguments, in whichever
    /// register or stack position that competitive allocation naturally
    /// produces — exactly matching `argumentLocations`' own competitive
    /// cursor. Forcing them into fixed registers regardless of argument
    /// count is an ABI mismatch, not merely a missing feature.
    var directForwardingOutgoingStackSources: [OutgoingStackSource]? {
        guard let dynamicSelfLocations,
            typedErrorDestinationLocation?.isStack != true
        else {
            return nil
        }
        var sources: [(offset: Int, source: OutgoingStackSource)] = []
        for location in argumentLocations.flatMap({ $0 }) {
            guard case .stack(let offset) = location.storage else { continue }
            sources.append((offset, .argument(location)))
        }
        if case .stack(let offset) = dynamicSelfLocations.metadata.storage {
            sources.append((offset, .metadata))
        }
        if case .stack(let offset) = dynamicSelfLocations.witnessTable.storage {
            sources.append((offset, .witnessTable))
        }
        guard sources.count <= Self.maximumOutgoingStackWords else {
            return nil
        }
        return sources.sorted { $0.offset < $1.offset }.map(\.source)
    }

    var typedAdapterInvocationArgumentIndex: Int? {
        guard let typedAdapterInvocationLocation,
            case .generalPurposeRegister(let index) =
                typedAdapterInvocationLocation.storage
        else {
            return nil
        }
        return index
    }
}

extension CallFrameArgumentLocation {
    fileprivate var isStack: Bool {
        if case .stack = storage { return true }
        return false
    }
}
