import Testing
import TestDoublesResilientFixtures
@testable import TestDoubles

/// Declaring the requirement and its conformer in the client module makes the
/// client's compiler choose the imported values' calling conventions.
protocol ResilientValueArgumentABIProbe {
    func accept(
        marker: UInt64,
        value: ResilientValueArgument,
        laterMarker: UInt64
    ) -> UInt64

    func acceptFrozen(
        marker: UInt64,
        value: FrozenValueArgument,
        laterMarker: UInt64
    ) -> UInt64

    func acceptFrozenFloating(_ value: FrozenFloatingValueArgument) -> Double

    func acceptAsync(
        value: ResilientValueArgument,
        laterMarker: UInt64
    ) async -> UInt64
}

protocol ResilientValueSetterABIProbe {
    subscript(_ index: UInt64) -> ResilientValueArgument { get set }
}

private struct LiveResilientValueArgumentABIProbe: ResilientValueArgumentABIProbe {
    func accept(
        marker: UInt64,
        value: ResilientValueArgument,
        laterMarker: UInt64
    ) -> UInt64 {
        marker ^ value.first ^ value.second ^ laterMarker
    }

    func acceptFrozen(
        marker: UInt64,
        value: FrozenValueArgument,
        laterMarker: UInt64
    ) -> UInt64 {
        marker ^ value.first ^ value.second ^ laterMarker
    }

    func acceptFrozenFloating(_ value: FrozenFloatingValueArgument) -> Double {
        value.first + value.second
    }

    func acceptAsync(
        value: ResilientValueArgument,
        laterMarker: UInt64
    ) async -> UInt64 {
        value.first ^ value.second ^ laterMarker
    }
}

private struct LiveResilientValueSetterABIProbe:
    ResilientValueSetterABIProbe
{
    subscript(index: UInt64) -> ResilientValueArgument {
        get { ResilientValueArgument(first: index, second: index) }
        set {}
    }
}

@Suite struct ResilientValueArgumentABITests {
    @Test func importedResilientValueUsesTheClientsIndirectConvention() throws {
        _ = LiveResilientValueArgumentABIProbe()
        let placeholder = ResilientValueArgument(
            first: 0x91E4_C72A_5B38_D60F,
            second: 0x2D7B_A905_EC61_43F8
        )
        let value = ResilientValueArgument(
            first: 0xA17C_49D2_EB05_73C1,
            second: 0x6E38_B4F9_2CAD_8507
        )
        let marker: UInt64 = 0xD3C7_9A42_51E8_B60F
        let laterMarker: UInt64 = 0x8B26_FD91_47CA_305E
        let stub = try Stub<any ResilientValueArgumentABIProbe>()
        stub.when {
            $0.accept(
                marker: Match.any(),
                value: Match.any(using: placeholder),
                laterMarker: Match.any()
            )
        }.then {
            (marker: UInt64, value: ResilientValueArgument, laterMarker: UInt64) in
            marker ^ value.first ^ value.second ^ laterMarker
        }

        let result = stub().accept(
            marker: marker,
            value: value,
            laterMarker: laterMarker
        )

        #expect(result == marker ^ value.first ^ value.second ^ laterMarker)
        stub.verify {
            $0.accept(
                marker: Match.equal(marker),
                value: Match.equal(value),
                laterMarker: Match.equal(laterMarker)
            )
        }
    }

    @Test func importedFrozenValueRemainsDirect() throws {
        _ = LiveResilientValueArgumentABIProbe()
        let placeholder = FrozenValueArgument(
            first: 0x91E4_C72A_5B38_D60F,
            second: 0x2D7B_A905_EC61_43F8
        )
        let value = FrozenValueArgument(
            first: 0xA17C_49D2_EB05_73C1,
            second: 0x6E38_B4F9_2CAD_8507
        )
        let marker: UInt64 = 0xD3C7_9A42_51E8_B60F
        let laterMarker: UInt64 = 0x8B26_FD91_47CA_305E
        let stub = try Stub<any ResilientValueArgumentABIProbe>()
        stub.when {
            $0.acceptFrozen(
                marker: Match.any(),
                value: Match.any(using: placeholder),
                laterMarker: Match.any()
            )
        }.then {
            (marker: UInt64, value: FrozenValueArgument, laterMarker: UInt64) in
            marker ^ value.first ^ value.second ^ laterMarker
        }

        let result = stub().acceptFrozen(
            marker: marker,
            value: value,
            laterMarker: laterMarker
        )

        #expect(result == marker ^ value.first ^ value.second ^ laterMarker)
        stub.verify {
            $0.acceptFrozen(
                marker: Match.equal(marker),
                value: Match.equal(value),
                laterMarker: Match.equal(laterMarker)
            )
        }
    }

    @Test func importedFrozenFloatingAggregateRemainsDirect() throws {
        let placeholder = FrozenFloatingValueArgument(
            first: 91_234.567_89,
            second: -76_543.210_98
        )
        let stub = try Stub<any ResilientValueArgumentABIProbe>()
        stub.when {
            $0.acceptFrozenFloating(Match.any(using: placeholder))
        }.then { (value: FrozenFloatingValueArgument) in
            value.first + value.second
        }

        let value = FrozenFloatingValueArgument(first: 12.5, second: 3.25)
        #expect(stub().acceptFrozenFloating(value) == 15.75)
    }

    @Test func calibratedResilientValueForwardsWithTheSelectedLayout() throws {
        let placeholder = ResilientValueArgument(
            first: 0x91E4_C72A_5B38_D60F,
            second: 0x2D7B_A905_EC61_43F8
        )
        let spy = try Spy<any ResilientValueArgumentABIProbe>(
            forwardingTo: LiveResilientValueArgumentABIProbe()
        )
        spy.when {
            $0.accept(
                marker: Match.any(),
                value: Match.any(using: placeholder),
                laterMarker: Match.any()
            )
        }.thenForward()

        let value = ResilientValueArgument(first: 17, second: 29)
        #expect(
            spy().accept(marker: 3, value: value, laterMarker: 5)
                == 3 ^ 17 ^ 29 ^ 5
        )
    }

    @Test func asyncResilientValueUsesTheCalibratedStackPlan() async throws {
        let placeholder = ResilientValueArgument(first: 101, second: 103)
        let stub = try Stub<any ResilientValueArgumentABIProbe>()
        await stub.when {
            await $0.acceptAsync(
                value: Match.any(using: placeholder),
                laterMarker: Match.any()
            )
        }.then {
            (value: ResilientValueArgument, laterMarker: UInt64) async in
            value.first ^ value.second ^ laterMarker
        }

        let value = ResilientValueArgument(first: 107, second: 109)
        #expect(
            await stub().acceptAsync(value: value, laterMarker: 113)
                == 107 ^ 109 ^ 113
        )
    }

    @Test func resilientSubscriptSetterKeepsValueFirstABIOrder() throws {
        let placeholder = ResilientValueArgument(first: 127, second: 131)
        let value = ResilientValueArgument(first: 137, second: 139)
        let stub = try Spy<any ResilientValueSetterABIProbe>(
            forwardingTo: LiveResilientValueSetterABIProbe()
        )
        stub.when {
            $0[Match.equal(149)] = Match.any(using: placeholder)
        }.then { (received: ResilientValueArgument, index: UInt64) in
            #expect(received == value)
            #expect(index == 149)
        }

        var probe: any ResilientValueSetterABIProbe = stub()
        probe[149] = value
        stub.verify {
            $0[Match.equal(149)] = Match.equal(value)
        }
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct ResilientValueArgumentABIExitTests {
        @Test func literalOnlyRecordingFailsBeforeTypedDecoding() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any ResilientValueArgumentABIProbe>()
                _ = stub.when {
                    $0.accept(
                        marker: 1,
                        value: ResilientValueArgument(first: 2, second: 3),
                        laterMarker: 4
                    )
                }
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(
                diagnostic.contains(
                    "Record the call with one Match expression for every argument"
                )
            )
        }
    }
#endif
