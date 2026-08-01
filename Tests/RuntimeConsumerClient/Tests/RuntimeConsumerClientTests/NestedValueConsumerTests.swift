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

    @Test func genericParentsOfNestedValueArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any GenericNestedEnvelopeGateway>()
        let placeholder = ExternalGenericAPI<ExternalReservation>.Envelope(
            payload: ExternalReservation(start: 10, end: 12),
            metadata: "placeholder"
        )
        stub.when { $0.submit(Match.any(using: placeholder)) }
            .then {
                (
                    envelope: ExternalGenericAPI<ExternalReservation>.Envelope<String>
                ) in
                envelope.payload.start + UInt64(envelope.metadata.count)
            }

        let actual = stub().submit(
            ExternalGenericAPI<ExternalReservation>.Envelope(
                payload: ExternalReservation(start: 30, end: 34),
                metadata: "live"
            )
        )
        #expect(actual == 34)
    }

    @Test func genericParentsOfNonGenericValueArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any GenericParentStatusGateway>()
        let placeholder = ExternalGenericAPI<ExternalReservation>.Status(
            payload: ExternalReservation(start: 10, end: 12)
        )
        stub.when { $0.submit(Match.any(using: placeholder)) }
            .then { (status: ExternalGenericAPI<ExternalReservation>.Status) in
                status.payload.end - status.payload.start
            }

        let actual = stub().submit(
            ExternalGenericAPI<ExternalReservation>.Status(
                payload: ExternalReservation(start: 30, end: 34)
            )
        )
        #expect(actual == 4)
    }
}
