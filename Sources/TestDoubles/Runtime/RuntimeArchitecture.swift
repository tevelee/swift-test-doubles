enum RuntimeArchitecture: Equatable, Sendable {
    case arm64
    case x86_64

    static var current: Self {
        #if arch(x86_64)
            .x86_64
        #else
            .arm64
        #endif
    }

    var generalPurposeArgumentRegisterCount: Int {
        switch self {
            case .arm64: 8
            case .x86_64: 6
        }
    }

    var vectorArgumentRegisterCount: Int { 8 }
}
