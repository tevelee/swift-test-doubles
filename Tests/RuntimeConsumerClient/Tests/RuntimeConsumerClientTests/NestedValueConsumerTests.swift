import ConsumerFixtures
import TestDoubles
import Testing

@Suite struct NestedValueConsumerTests {
    @Test func nestedGenericValueArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any NestedGenericEnvelopeGateway>()
        let placeholder = ExternalAPI.Envelope(
            value: ExternalReservation(start: 10, end: 12)
        )
        stub.when { $0.submit(Match.any(using: placeholder)) }
            .then { (envelope: ExternalAPI.Envelope<ExternalReservation>) in
                envelope.value.start ^ envelope.value.end
            }

        let actual = stub().submit(
            ExternalAPI.Envelope(
                value: ExternalReservation(start: 30, end: 34)
            )
        )
        #expect(actual == 30 ^ 34)
    }
}
