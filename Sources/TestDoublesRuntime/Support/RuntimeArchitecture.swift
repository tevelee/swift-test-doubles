package enum RuntimeStackArgumentLayout: Equatable, Sendable {
    case naturallyAligned
    case wordSlots
}

package enum RuntimeArchitecture: Equatable, Sendable {
    case arm64
    case x86_64

    package static var current: Self {
        #if arch(x86_64)
            .x86_64
        #else
            .arm64
        #endif
    }

    package var generalPurposeArgumentRegisterCount: Int {
        switch self {
            case .arm64: 8
            case .x86_64: 6
        }
    }

    package var vectorArgumentRegisterCount: Int { 8 }

    /// Swift's stack-slot policy depends on both CPU architecture and platform.
    /// Darwin arm64 follows natural value alignment, while non-Darwin arm64 and
    /// x86_64 reserve complete machine-word slots for these argument fragments.
    package var stackArgumentLayout: RuntimeStackArgumentLayout {
        switch self {
            case .arm64:
                #if canImport(Darwin)
                    .naturallyAligned
                #else
                    .wordSlots
                #endif
            case .x86_64:
                .wordSlots
        }
    }
}
