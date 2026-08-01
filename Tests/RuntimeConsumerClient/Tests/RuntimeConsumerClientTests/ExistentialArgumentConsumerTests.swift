import ConsumerFixtures
import TestDoubles
import Testing

@Suite struct ExistentialArgumentConsumerTests {
    @Test func concreteErrorMatchersCalibrateExistentialArguments() throws {
        let stub = try Stub<any FailureReporter>()
        let placeholder = ReservationFailure.unavailable(code: 29)
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (error: any Error) in
                String(describing: error)
            }

        #expect(
            stub().report(ReservationFailure.unavailable(code: 31))
                == "unavailable(code: 31)"
        )
    }

    @Test func concretePayloadMatchersCalibrateProtocolExistentialArguments() throws {
        let stub = try Stub<any PayloadReporter>()
        let placeholder = ExternalReportPayload(summary: "placeholder")
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (payload: any ReportPayload) in
                payload.summary
            }

        #expect(
            stub().report(ExternalReportPayload(summary: "actual")) == "actual"
        )
    }

    @Test func protocolCompositionArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any SendablePayloadReporter>()
        let placeholder = ExternalReportPayload(summary: "placeholder")
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (payload: any ReportPayload & Sendable) in
                payload.summary
            }

        #expect(
            stub().report(ExternalReportPayload(summary: "actual")) == "actual"
        )
    }

    @Test func multiProtocolCompositionArgumentsDecodeInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DetailedPayloadReporter>()
        let placeholder = ExternalReportPayload(
            summary: "placeholder",
            detail: "placeholder-detail"
        )
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (payload: any ReportPayload & DetailedReportPayload) in
                "\(payload.summary):\(payload.detail)"
            }

        #expect(
            stub().report(
                ExternalReportPayload(summary: "actual", detail: "actual-detail")
            ) == "actual:actual-detail"
        )
    }

    @Test func existentialMetatypeArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any PayloadMetatypeReporter>()
        let placeholder = ExternalReportPayload.self
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (type: any ReportPayload.Type) in
                String(reflecting: type)
            }

        #expect(stub().report(ExternalReportPayload.self).contains("ExternalReportPayload"))
    }

    @Test func classConstrainedProtocolCompositionArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any ClassConstrainedPayloadReporter>()
        let placeholder = ExternalReferenceReportPayload(summary: "placeholder")
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (payload: any ReportPayload & AnyObject) in
                payload.summary
            }

        #expect(
            stub().report(ExternalReferenceReportPayload(summary: "actual")) == "actual"
        )
    }

    @Test func nestedProtocolArgumentsResolveInAnOrdinaryConsumer() throws {
        let stub = try Stub<any NestedPayloadReporter>()
        let placeholder = NestedPayloadNamespace.Value(summary: "placeholder")
        stub.when { $0.report(Match.any(using: placeholder)) }
            .then { (payload: any NestedPayloadNamespace.Payload) in
                payload.summary
            }

        #expect(
            stub().report(NestedPayloadNamespace.Value(summary: "actual")) == "actual"
        )
    }
}
