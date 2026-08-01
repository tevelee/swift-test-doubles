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

    func acceptStatus(_ value: ResilientEnumArgument) -> String

    func acceptAsync(
        value: ResilientValueArgument,
        laterMarker: UInt64
    ) async -> UInt64
}

protocol ResilientValueBatchABIProbe {
    func acceptBatch(
        _ first: ResilientValueArgument,
        _ second: ResilientValueArgument,
        _ third: ResilientValueArgument,
        _ fourth: ResilientValueArgument,
        _ fifth: ResilientValueArgument,
        _ sixth: ResilientValueArgument,
        _ seventh: ResilientValueArgument,
        _ eighth: ResilientValueArgument,
        _ ninth: ResilientValueArgument
    ) -> Int
}

protocol ResilientValueSetterABIProbe {
    subscript(_ index: UInt64) -> ResilientValueArgument { get set }
}

protocol ResilientTupleArgumentABIProbe {
    func accept(_ value: (ResilientValueArgument, UInt64)) -> Int
}

protocol ResilientTupleResultABIProbe {
    func makeValue() -> (ResilientValueArgument, UInt64)
}

protocol ResilientTypedErrorABIProbe {
    func load() throws(ResilientTypedError) -> Int
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

    func acceptStatus(_ value: ResilientEnumArgument) -> String {
        switch value {
            case .pending: return "pending"
            case .confirmed: return "confirmed"
        }
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

private struct LiveResilientTupleArgumentABIProbe: ResilientTupleArgumentABIProbe {
    func accept(_ value: (ResilientValueArgument, UInt64)) -> Int {
        Int(value.0.first ^ value.0.second ^ value.1)
    }
}

private struct LiveResilientTupleResultABIProbe: ResilientTupleResultABIProbe {
    func makeValue() -> (ResilientValueArgument, UInt64) {
        (ResilientValueArgument(first: 0, second: 0), 0)
    }
}

private struct LiveResilientTypedErrorABIProbe: ResilientTypedErrorABIProbe {
    func load() throws(ResilientTypedError) -> Int {
        throw ResilientTypedError(code: 1)
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

    @Test func importedResilientEnumUsesTheClientsIndirectConvention() throws {
        _ = LiveResilientValueArgumentABIProbe()
        let stub = try Stub<any ResilientValueArgumentABIProbe>()
        stub.when { $0.acceptStatus(Match.any(using: .pending)) }
            .then { (value: ResilientEnumArgument) in
                switch value {
                    case .pending: return "pending"
                    case .confirmed: return "confirmed"
                }
            }

        #expect(stub().acceptStatus(.confirmed) == "confirmed")
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

    @Test func calibratesMoreThanEightResilientArgumentsWithoutEnumeratingEveryLayout() throws {
        let values = (1 ... 9).map {
            ResilientValueArgument(first: UInt64($0), second: UInt64($0 + 100))
        }
        let stub = try Stub<any ResilientValueBatchABIProbe>(
            .method(
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                ResilientValueArgument.self,
                returning: Int.self
            )
        )
        stub.when {
            $0.acceptBatch(
                Match.any(using: values[0]),
                Match.any(using: values[1]),
                Match.any(using: values[2]),
                Match.any(using: values[3]),
                Match.any(using: values[4]),
                Match.any(using: values[5]),
                Match.any(using: values[6]),
                Match.any(using: values[7]),
                Match.any(using: values[8])
            )
        }.thenReturn(9)

        #expect(
            stub().acceptBatch(
                values[0],
                values[1],
                values[2],
                values[3],
                values[4],
                values[5],
                values[6],
                values[7],
                values[8]
            ) == 9
        )
    }

    @Test func resilientSubscriptGetterFailsBeforeItsResultCanCorrupt() {
        let error = #expect(throws: StubError.self) {
            _ = try Spy<any ResilientValueSetterABIProbe>(
                forwardingTo: LiveResilientValueSetterABIProbe()
            )
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
        #expect(error?.description.contains("cannot be calibrated") == true)
    }

    @Test func uncertainResilientResultsFailDuringConstruction() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ResilientValueResultABIProbe>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
        #expect(error?.description.contains("cannot be calibrated") == true)
    }

    @Test func tuplesWithResilientArgumentsFailBeforeMixedTransportCanCorrupt() {
        _ = LiveResilientTupleArgumentABIProbe()
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ResilientTupleArgumentABIProbe>()
        }
        #expect(error?.description.contains("tuple argument") == true)
        #expect(error?.description.contains("cannot be calibrated") == true)
    }

    @Test func tuplesWithResilientResultsFailBeforeMixedTransportCanCorrupt() {
        _ = LiveResilientTupleResultABIProbe()
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ResilientTupleResultABIProbe>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
        #expect(error?.description.contains("Tuple members are lowered independently") == true)
    }

    @Test func resilientTypedErrorsFailBeforeTheirResultSlotCanCorrupt() {
        _ = LiveResilientTypedErrorABIProbe()
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ResilientTypedErrorABIProbe>()
        }
        #expect(error?.description.contains("ABI-uncertain typed error") == true)
        #expect(error?.description.contains("cannot be calibrated") == true)
    }

    @Test func frozenResultsRemainSupported() throws {
        let expected = FrozenValueArgument(first: 151, second: 157)
        let stub = try Stub<any FrozenValueResultABIProbe>()
        stub.when { $0.makeValue() }.thenReturn(expected)

        #expect(stub().makeValue() == expected)
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
