import TestDoublesFixtures
import Testing
@testable import TestDoubles
@testable import TestDoublesRuntimeMetadata

/// Keeps each conformer's witness table reachable through release-mode dead-code
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

private func useLinkedGenericRequirementProbe(
    _ value: any ExternalGenericRequirementProbe
) -> Int {
    value.generic(1)
}

@Suite struct RequirementGenericSignatureTests {
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

    /// Parameter packs remain a special case of a broader shape: unlike a
    /// plain requirement-level generic parameter (see
    /// `GenericRequirementTests`), packs are variable-length per call site
    /// and stay unimplemented, so they alone still fail closed.
    @Test func plainRequirementLevelGenericParametersAreAutomaticallyDiscovered() throws {
        #expect(
            useLinkedGenericRequirementProbe(RealExternalGenericRequirementProbe())
                == MemoryLayout<Int>.size
        )

        let stub = try Stub<any ExternalGenericRequirementProbe>()
        stub.when { $0.generic(any(using: 0)) }.thenReturn(7)

        let probe: any ExternalGenericRequirementProbe = stub()
        #expect(probe.generic(123) == 7)
    }

    /// `Demangle::genericParameterName` prints depth-0 parameters as bare
    /// letters and deeper ones with the depth appended, so `Self` is `"A"` while
    /// a requirement's own first generic parameter is `"A1"`. Real types always
    /// demangle module-qualified, so a bare letter-plus-digits spelling is
    /// unambiguous.
    @Test func onlyRequirementLevelGenericParametersAreClassifiedAsSuch() {
        #expect(isMethodGenericParameter("A1"))
        #expect(isMethodGenericParameter("B1"))
        #expect(isMethodGenericParameter("A2"))

        #expect(isMethodGenericParameter("A") == false)
        #expect(isMethodGenericParameter("Self") == false)
        #expect(isMethodGenericParameter("A.Value") == false)
        #expect(isMethodGenericParameter("Swift.Int") == false)
        #expect(isMethodGenericParameter("MyModule.A1") == false)
        #expect(isMethodGenericParameter("") == false)
        #expect(isMethodGenericParameter("1A") == false)
    }
}
