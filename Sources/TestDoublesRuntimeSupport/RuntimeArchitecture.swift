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
}
