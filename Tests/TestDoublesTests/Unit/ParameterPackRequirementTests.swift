import Testing
@testable import TestDoubles

private protocol PackRequirementProbe {
    func f<each T>(_ args: repeat each T)
}

private struct LinkedPackRequirementProbe: PackRequirementProbe {
    func f<each T>(_ args: repeat each T) {}
}

@Suite struct ParameterPackRequirementTests {
    @Test func requirementsWithTheirOwnParameterPackFailClosedWithASpecificDiagnostic() {
        expectUnsupportedProtocolShape(
            containing: "parameter-pack argument"
        ) {
            _ = try Stub<PackRequirementProbe>()
        }
    }
}
