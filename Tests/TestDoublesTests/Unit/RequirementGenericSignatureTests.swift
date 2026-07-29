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

@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
private func useLinkedConstrainedPackRequirementProbe(
    _ value: any ExternalConstrainedPackRequirementProbe
) -> Int {
    value.pack(ExternalGenericConstraintValue())
}

@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
private func useLinkedMultiplePackRequirementProbe(
    _ value: any ExternalMultiplePackRequirementProbe
) -> Int {
    value.pack(1, second: "two")
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
    func requirementsWithTheirOwnParameterPackCaptureEveryElement() throws {
        #expect(
            useLinkedPackRequirementProbe(RealExternalPackRequirementProbe()) == 2
        )

        let integerCaptor = Match.Capture<Int>()
        let textCaptor = Match.Capture<String>()
        let stub = try Stub<any ExternalPackRequirementProbe>()
        stub.when { $0.pack() }.thenReturn(0)
        stub.when {
            $0.pack(
                integerCaptor.capture(using: 0),
                textCaptor.capture(using: "")
            )
        }.then { (integer: Int, text: String) in
            integer + text.count
        }
        stub.when { $0.pack(1, "two", true) }.thenReturn(3)

        let probe: any ExternalPackRequirementProbe = stub()
        #expect(probe.pack() == 0)
        #expect(probe.pack(40, "go") == 42)
        #expect(probe.pack(1, "two", true) == 3)

        #expect(integerCaptor.values == [40])
        #expect(textCaptor.values == ["go"])

        let recorded: [(Int, String)] = stub.invocations { $0.pack(40, "go") }
        #expect(recorded.count == 1)
        #expect(recorded[0].0 == 40)
        #expect(recorded[0].1 == "go")

        stub.verify { $0.pack() }
        stub.verify { $0.pack(40, "go") }
        stub.verify { $0.pack(1, "two", true) }
    }

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
    func constrainedAndMultipleRequirementPacksFailClosed() {
        #expect(
            useLinkedConstrainedPackRequirementProbe(
                RealExternalConstrainedPackRequirementProbe()
            ) == 1
        )
        #expect(
            useLinkedMultiplePackRequirementProbe(
                RealExternalMultiplePackRequirementProbe()
            ) == 2
        )

        expectUnsupportedProtocolShape(containing: "generic signature") {
            _ = try Stub<any ExternalConstrainedPackRequirementProbe>()
        }
        expectUnsupportedProtocolShape(containing: "one standalone") {
            _ = try Stub<any ExternalMultiplePackRequirementProbe>()
        }
        expectUnsupportedProtocolShape(containing: "Async continuation transport") {
            _ = try Stub<any ExternalAsyncPackRequirementProbe>()
        }
        expectUnsupportedProtocolShape(containing: "returns a parameter pack") {
            _ = try Stub<any ExternalPackResultRequirementProbe>()
        }
        expectUnsupportedProtocolShape(containing: "Forwarding Spy does not support") {
            _ = try Spy<any ExternalPackRequirementProbe>(
                forwardingTo: RealExternalPackRequirementProbe()
            )
        }
    }

    /// Ordinary method generic parameters use a distinct metadata-word ABI.
    @Test func plainRequirementLevelGenericParametersAreAutomaticallyDiscovered() throws {
        #expect(
            useLinkedGenericRequirementProbe(RealExternalGenericRequirementProbe())
                == MemoryLayout<Int>.size
        )

        let stub = try Stub<any ExternalGenericRequirementProbe>()
        stub.when { $0.generic(Match.any(using: 0)) }.thenReturn(7)

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
        #expect(methodGenericParameterIndex("Z1") == 25)
        #expect(methodGenericParameterIndex("AB1") == 26)
        #expect(methodGenericParameterIndex("BB1") == 27)
        #expect(methodGenericParameterIndex("AZ1") == 650)
        #expect(methodGenericParameterPackIndex("repeat A1") == 0)
        #expect(methodGenericParameterPackIndex("(repeat A1)") == 0)

        #expect(isMethodGenericParameter("A") == false)
        #expect(isMethodGenericParameter("Self") == false)
        #expect(isMethodGenericParameter("A.Value") == false)
        #expect(isMethodGenericParameter("Swift.Int") == false)
        #expect(isMethodGenericParameter("MyModule.A1") == false)
        #expect(isMethodGenericParameter("") == false)
        #expect(isMethodGenericParameter("1A") == false)
        #expect(methodGenericParameterPackIndex("repeat A1, repeat B1") == nil)
        #expect(methodGenericParameterIndex(String(repeating: "Z", count: 32) + "1") == nil)
    }
}
