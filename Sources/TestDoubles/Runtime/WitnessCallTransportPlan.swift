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
    /// when the complete call stays inside the captured register banks.
    var directForwardingHiddenArgumentIndex: Int? {
        guard decodedStackByteCount == 0,
            hiddenStackByteCount == 0
        else {
            return nil
        }
        return dynamicSelfLocations?.consecutiveRegisterStart
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
