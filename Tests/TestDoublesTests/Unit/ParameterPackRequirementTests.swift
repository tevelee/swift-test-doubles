import TestDoublesFixtures
import Testing
@testable import TestDoubles

/// Keeps the conformer's witness table reachable through release-mode dead-code
/// elimination, so automatic discovery reaches the requirement itself rather
/// than failing earlier for lack of any linked conformer.
@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
private func useLinkedPackRequirementProbe(
    _ value: any ExternalPackRequirementProbe
) -> Int {
    value.pack(1, "two")
}

@Suite struct ParameterPackRequirementTests {
    @Test
    @available(
        macOS 14.0,
        iOS 17.0,
        tvOS 17.0,
        watchOS 10.0,
        visionOS 1.0,
        macCatalyst 17.0,
        *
    )
    func requirementsWithTheirOwnParameterPackFailClosedWithASpecificDiagnostic() {
        #expect(
            useLinkedPackRequirementProbe(RealExternalPackRequirementProbe()) == 2
        )

        expectUnsupportedProtocolShape(
            containing: "parameter-pack argument"
        ) {
            _ = try Stub<any ExternalPackRequirementProbe>()
        }
    }
}
