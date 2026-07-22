import Echo

/// The bounded direct-closure argument layout accepted by the dynamic bridge.
///
/// A stack-bearing plan contains exactly one complete general-purpose word at
/// stack offset zero. Wider, split, padded, and vector spills remain outside
/// the source-less bridge because they require additional ABI-specific staging.
struct DynamicFunctionArgumentPlan: Sendable {
    let layouts: [ABIClass]
    let usesStackArgument: Bool
}

func dynamicFunctionArgumentPlan(
    _ types: [Any.Type],
    initialGeneralPurposeOffset: Int = 0,
    trailingGeneralPurposeWordCount: Int = 0,
    architecture: RuntimeArchitecture = .current
) -> DynamicFunctionArgumentPlan? {
    let layouts = types.map { abiClass(for: $0) }
    let shapes = zip(types, layouts).map {
        CallFrameArgumentShape(type: $0.0, layout: $0.1)
    }
    let locationPlan = CallFrameArgumentLocationPlan(
        arguments: shapes,
        initialGeneralPurposeOffset: initialGeneralPurposeOffset,
        trailingGeneralPurposeWordCount: trailingGeneralPurposeWordCount,
        architecture: architecture
    )

    var stackLocations: [CallFrameArgumentLocation] = []
    var spilledArgumentIndex: Int?
    for (argumentIndex, locations) in locationPlan.arguments.enumerated() {
        for location in locations {
            guard case .stack = location.storage else { continue }
            stackLocations.append(location)
            spilledArgumentIndex = argumentIndex
        }
    }
    for location in locationPlan.trailingGeneralPurpose {
        guard case .stack = location.storage else { continue }
        stackLocations.append(location)
    }

    guard stackLocations.isEmpty == false else {
        return DynamicFunctionArgumentPlan(
            layouts: layouts,
            usesStackArgument: false
        )
    }
    guard stackLocations.count == 1,
        locationPlan.stackByteCount == MemoryLayout<UInt>.size,
        stackLocations[0].storage == .stack(byteOffset: 0),
        stackLocations[0].valueOffset == 0,
        stackLocations[0].byteCount == MemoryLayout<UInt>.size
    else {
        return nil
    }

    if let spilledArgumentIndex {
        let shape = shapes[spilledArgumentIndex]
        guard shape.pieces.count == 1,
            shape.pieces[0].register == .gp,
            shape.pieces[0].valueOffset == 0,
            shape.pieces[0].byteCount == MemoryLayout<UInt>.size
        else {
            return nil
        }
    }
    return DynamicFunctionArgumentPlan(
        layouts: layouts,
        usesStackArgument: true
    )
}

func dynamicGenericArgumentLimit(
    architecture: RuntimeArchitecture = .current
) -> Int {
    architecture.generalPurposeArgumentRegisterCount + 1
}

/// Returns the continuation-SP adjustment consumed by a dynamic async callee.
///
/// arm64 rounds one spilled word up to its 16-byte stack alignment. x86_64's
/// live return/job slot already accounts for that word, so its net adjustment
/// remains zero.
func dynamicAsyncStackAdjustmentByteCount(
    usesStackArgument: Bool,
    architecture: RuntimeArchitecture = .current
) -> Int {
    guard usesStackArgument else { return 0 }
    return switch architecture {
        case .arm64:
            2 * MemoryLayout<UInt>.size
        case .x86_64:
            0
    }
}
