import ConsumerFixtures
import Foundation
import TestDoubles
import Testing

private protocol DeliveryGateway: Sendable {
    func schedule(
        destination: URL,
        window: ClosedRange<ExternalReservation>,
        notes: URL??
    ) -> Int

    func day(_ window: ClosedRange<Date>) -> Int

    func map(_ point: FrozenExternalPoint) -> UInt64
}

private protocol ReservationSource {
    func currentReservation() -> ExternalReservation
}

private struct LiveDeliveryGateway: DeliveryGateway, Sendable {
    func schedule(
        destination: URL,
        window: ClosedRange<ExternalReservation>,
        notes: URL??
    ) -> Int {
        destination.absoluteString.count
            + Int(window.lowerBound.start)
            + (notes == nil ? 0 : 1)
    }

    func day(_ window: ClosedRange<Date>) -> Int {
        Int(window.lowerBound.timeIntervalSinceReferenceDate)
    }

    func map(_ point: FrozenExternalPoint) -> UInt64 {
        point.x ^ point.y
    }
}

private struct LiveReservationSource: ReservationSource {
    func currentReservation() -> ExternalReservation {
        ExternalReservation(start: 1, end: 2)
    }
}

@Suite struct RuntimeConsumerClientTests {
    @Test func importedAndGenericValuesDecodeInAnOrdinaryConsumer() throws {
        _ = LiveDeliveryGateway()
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
        _ = LiveDeliveryGateway()
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
        _ = LiveDeliveryGateway()
        let stub = try Stub<any DeliveryGateway>()
        let placeholder = FrozenExternalPoint(x: 1, y: 2)
        stub.when { $0.map(Match.any(using: placeholder)) }.then {
            (point: FrozenExternalPoint) in
            point.x ^ point.y
        }

        #expect(stub().map(FrozenExternalPoint(x: 5, y: 9)) == 12)
    }

    @Test func uncertainImportedResultsFailBeforeInvocation() {
        _ = LiveReservationSource()
        #expect(throws: StubError.self) {
            _ = try Stub<any ReservationSource>()
        }
    }
}
