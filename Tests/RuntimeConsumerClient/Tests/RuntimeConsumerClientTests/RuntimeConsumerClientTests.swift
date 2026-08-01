import ConsumerFixtures
import Foundation
import TestDoubles
import Testing

@Suite struct RuntimeConsumerClientTests {
    @Test func importedAndGenericValuesDecodeInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let destination = URL(string: "https://example.com/delivery")!
        let window =
            ExternalReservation(start: 10, end: 12)
            ... ExternalReservation(start: 20, end: 24)
        let notesURL = URL(string: "https://example.com/notes")!

        stub.when {
            $0.schedule(
                destination: Match.any(using: destination),
                window: Match.any(using: window),
                notes: Match.any(using: notesURL)
            )
        }.then {
            (destination: URL, window: ClosedRange<ExternalReservation>, notes: URL??) in
            let noteCount: Int
            if case .some(.some(let receivedNotesURL)) = notes,
                receivedNotesURL == notesURL
            {
                noteCount = 1
            } else {
                noteCount = 0
            }
            return destination.absoluteString.count + Int(window.upperBound.end)
                + noteCount
        }

        let actualDestination = URL(string: "https://example.com/actual")!
        let actualWindow =
            ExternalReservation(start: 30, end: 32)
            ... ExternalReservation(start: 40, end: 44)
        #expect(
            stub().schedule(
                destination: actualDestination,
                window: actualWindow,
                notes: .some(.some(notesURL))
            ) == actualDestination.absoluteString.count + 44 + 1
        )
    }

    @Test func foundationRangeCalibratesWithoutTypeSpecificRuntimeLogic() throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder =
            Date(timeIntervalSinceReferenceDate: 10)
            ... Date(timeIntervalSinceReferenceDate: 20)
        stub.when { $0.day(Match.any(using: placeholder)) }.thenReturn(17)

        let actual =
            Date(timeIntervalSinceReferenceDate: 30)
            ... Date(timeIntervalSinceReferenceDate: 40)
        #expect(stub().day(actual) == 17)
    }

    @Test func forwardingReusesTheCalibratedImportedValuePlan() throws {
        let spy = try Spy<any DeliveryGateway>(
            forwardingTo: LiveDeliveryGateway()
        )
        let destination = URL(string: "https://example.com/delivery")!
        let window =
            ExternalReservation(start: 10, end: 12)
            ... ExternalReservation(start: 20, end: 24)
        let notesURL = URL(string: "https://example.com/notes")!
        spy.when {
            $0.schedule(
                destination: Match.any(using: destination),
                window: Match.any(using: window),
                notes: Match.any(using: notesURL)
            )
        }.thenForward()

        let actualDestination = URL(string: "https://example.com/actual")!
        let actualWindow =
            ExternalReservation(start: 30, end: 32)
            ... ExternalReservation(start: 40, end: 44)
        #expect(
            spy().schedule(
                destination: actualDestination,
                window: actualWindow,
                notes: .some(.some(notesURL))
            ) == actualDestination.absoluteString.count + 30 + 1
        )
    }

    @Test func frozenImportedValuesRemainDirectInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder = FrozenExternalPoint(x: 1, y: 2)
        stub.when { $0.map(Match.any(using: placeholder)) }.then {
            (point: FrozenExternalPoint) in
            point.x ^ point.y
        }

        #expect(stub().map(FrozenExternalPoint(x: 5, y: 9)) == 12)
    }

    @Test func wrappedResilientTuplesCalibrateInAnOrdinaryConsumer() throws {
        let optionalTupleStub = try Stub<any DeliveryGateway>()
        let optionalPlaceholder: (ExternalReservation, UInt64)? = (
            ExternalReservation(start: 3, end: 5),
            7
        )
        optionalTupleStub.when {
            $0.settle(Match.any(using: optionalPlaceholder))
        }.then { (value: (ExternalReservation, UInt64)?) in
            guard let value else { return 0 }
            return Int(value.0.start ^ value.0.end ^ value.1)
        }

        let optionalActual: (ExternalReservation, UInt64)? = (
            ExternalReservation(start: 11, end: 13),
            17
        )
        #expect(optionalTupleStub().settle(optionalActual) == 11 ^ 13 ^ 17)
        #expect(optionalTupleStub().settle(nil) == 0)

        let nominalShellStub = try Stub<any DeliveryGateway>()
        let nominalPlaceholder = ReservationEnvelope(
            reservation: ExternalReservation(start: 19, end: 23),
            identifier: 29
        )
        nominalShellStub.when {
            $0.deliver(Match.any(using: nominalPlaceholder))
        }.then { (value: ReservationEnvelope) in
            Int(value.payload.0.start ^ value.payload.0.end ^ value.payload.1)
        }

        let nominalActual = ReservationEnvelope(
            reservation: ExternalReservation(start: 31, end: 37),
            identifier: 41
        )
        #expect(nominalShellStub().deliver(nominalActual) == 31 ^ 37 ^ 41)
    }

    @Test func genericTupleShellsCalibrateInAnOrdinaryConsumer() throws {
        let boxStub = try Stub<any DeliveryGateway>()
        let boxPlaceholder: ReservationBox<(ExternalReservation, UInt64)> = ReservationBox(
            (ExternalReservation(start: 43, end: 47), 53)
        )
        boxStub.when { $0.package(Match.any(using: boxPlaceholder)) }
            .then { (value: ReservationBox<(ExternalReservation, UInt64)>) in
                Int(value.value.0.start ^ value.value.0.end ^ value.value.1)
            }

        let boxActual: ReservationBox<(ExternalReservation, UInt64)> = ReservationBox(
            (ExternalReservation(start: 59, end: 61), 67)
        )
        #expect(boxStub().package(boxActual) == 59 ^ 61 ^ 67)

        let resultStub = try Stub<any DeliveryGateway>()
        let resultPlaceholder: Result<(ExternalReservation, UInt64), Never> =
            .success((ExternalReservation(start: 71, end: 73), 79))
        resultStub.when { $0.resolve(Match.any(using: resultPlaceholder)) }
            .then { (value: Result<(ExternalReservation, UInt64), Never>) in
                switch value {
                    case .success(let value):
                        return Int(value.0.start ^ value.0.end ^ value.1)
                    case .failure(let impossible):
                        switch impossible {}
                }
            }

        let resultActual: Result<(ExternalReservation, UInt64), Never> =
            .success((ExternalReservation(start: 83, end: 89), 97))
        #expect(resultStub().resolve(resultActual) == 83 ^ 89 ^ 97)

        let outcomeStub = try Stub<any DeliveryGateway>()
        let outcomePlaceholder:
            Result<
                (ExternalReservation, UInt64), ReservationFailure
            > = .success((ExternalReservation(start: 101, end: 103), 107))
        outcomeStub.when { $0.resolveOutcome(Match.any(using: outcomePlaceholder)) }
            .then {
                (value: Result<(ExternalReservation, UInt64), ReservationFailure>) in
                switch value {
                    case .success(let value):
                        return "reservation:\(value.0.start ^ value.0.end ^ value.1)"
                    case .failure(.unavailable(let code)):
                        return "failure:\(code)"
                }
            }

        #expect(
            outcomeStub().resolveOutcome(.failure(.unavailable(code: 109)))
                == "failure:109"
        )
    }

    @Test func uncertainImportedResultsFailBeforeInvocation() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ReservationSource>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
    }
}
