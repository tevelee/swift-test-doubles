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

    @Test func genericExistentialArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any GenericPayloadReporter>()
        let placeholder: ExternalAPI.Envelope<any ReportPayload & DetailedReportPayload> = .init(
            value: ExternalReportPayload(summary: "placeholder")
        )
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (envelope: ExternalAPI.Envelope<any ReportPayload & DetailedReportPayload>) in
                "\(envelope.value.summary):\(envelope.value.detail)"
            }

        let actual = stub().report(
            .init(value: ExternalReportPayload(summary: "draft", detail: "ready"))
        )
        #expect(actual == "draft:ready")
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

    @Test func genericParentsOfExistentialArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any GenericParentPayloadReporter>()
        let placeholder: ExternalGenericAPI<any ReportPayload & DetailedReportPayload>.Status = .init(
            payload: ExternalReportPayload(summary: "placeholder")
        )
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then {
                (
                    status: ExternalGenericAPI<any ReportPayload & DetailedReportPayload>.Status
                ) in
                "\(status.payload.summary):\(status.payload.detail)"
            }

        let actual = stub().report(
            .init(payload: ExternalReportPayload(summary: "draft", detail: "ready"))
        )
        #expect(actual == "draft:ready")
    }

    @Test func genericParentsOfClosureArgumentsResolveInAnOrdinaryConsumer() throws {
        let placeholder: @Sendable (Int) -> Int = { $0 + 1 }
        let stub = try Stub<any GenericClosurePayloadGateway>()
        stub.when {
            $0.submit(
                Match.any(
                    using: ExternalGenericAPI<@Sendable (Int) -> Int>.Status(
                        payload: placeholder
                    )
                )
            )
        }.then { (status: ExternalGenericAPI<@Sendable (Int) -> Int>.Status) in
            status.payload(41)
        }

        let actual = stub().submit(.init(payload: { value in value + 2 }))
        #expect(actual == 43)
    }

    @Test func genericClosurePayloadsRecalculateFollowingArgumentLocations() throws {
        let placeholder: @Sendable (Int) -> Int = { $0 + 1 }
        let stub = try Stub<any GenericClosurePayloadWithMarkersGateway>()
        stub.when {
            $0.submit(
                prefix: Match.any(),
                status: Match.any(
                    using: ExternalGenericAPI<@Sendable (Int) -> Int>.Status(
                        payload: placeholder
                    )
                ),
                suffix: Match.any()
            )
        }.then {
            (
                prefix: UInt64,
                status: ExternalGenericAPI<@Sendable (Int) -> Int>.Status,
                suffix: UInt64
            ) in
            status.payload(Int(prefix + suffix))
        }

        let actual = stub().submit(
            prefix: 19,
            status: .init(payload: { value in value * 2 }),
            suffix: 23
        )
        #expect(actual == 84)
    }

    @Test func asyncGenericClosurePayloadsCalibrateInAnOrdinaryConsumer() async throws {
        let placeholder: @Sendable (Int) -> Int = { $0 + 1 }
        let stub = try Stub<any AsyncGenericClosurePayloadGateway>()
        await stub.when {
            await $0.submit(
                Match.any(
                    using: ExternalGenericAPI<@Sendable (Int) -> Int>.Status(
                        payload: placeholder
                    )
                )
            )
        }.then { (status: ExternalGenericAPI<@Sendable (Int) -> Int>.Status) async in
            status.payload(41)
        }

        let actual = await stub().submit(.init(payload: { value in value + 2 }))
        #expect(actual == 43)
    }

    @Test func genericClosurePayloadResultsFailBeforeInvocation() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any GenericClosurePayloadSource>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
        #expect(error?.description.contains("hand-written test double") == true)
    }

    @Test func frozenGenericClosurePayloadsRetainDirectTransport() throws {
        let placeholder: @Sendable (Int) -> Int = { $0 + 1 }
        let stub = try Stub<any FrozenGenericClosurePayloadGateway>()
        stub.when {
            $0.submit(
                Match.any(
                    using: FrozenExternalGenericBox(value: placeholder)
                )
            )
        }.then { (box: FrozenExternalGenericBox<@Sendable (Int) -> Int>) in
            box.value(41)
        }

        let actual = stub().submit(.init(value: { value in value + 2 }))
        #expect(actual == 43)
    }

    @Test func genericClosureEnumPayloadsCalibrateInAnOrdinaryConsumer() throws {
        let placeholder: @Sendable (Int) -> Int = { $0 + 1 }
        let stub = try Stub<any GenericClosureChoiceGateway>()
        stub.when {
            $0.submit(
                Match.any(
                    using: ExternalGenericChoice.value(placeholder)
                )
            )
        }.then { (choice: ExternalGenericChoice<@Sendable (Int) -> Int>) in
            switch choice {
                case .value(let transform): transform(41)
                case .unavailable: 0
            }
        }

        let actual = stub().submit(.value { value in value + 2 })
        #expect(actual == 43)
    }

    @Test func constrainedGenericParentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any OrderedGenericParentStatusGateway>()
        let placeholder = OrderedExternalAPI<ExternalReservation>.Status(
            payload: ExternalReservation(start: 10, end: 12)
        )
        stub.when { $0.submit(Match.any(using: placeholder)) }
            .then { (status: OrderedExternalAPI<ExternalReservation>.Status) in
                status.payload.end - status.payload.start
            }

        let actual = stub().submit(
            OrderedExternalAPI<ExternalReservation>.Status(
                payload: ExternalReservation(start: 30, end: 34)
            )
        )
        #expect(actual == 4)
    }
}
