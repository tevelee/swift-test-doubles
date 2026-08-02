import ConsumerFixtures
import Foundation
import TestDoubles
import Testing

private struct ReservationStartingAtLeast: CustomMatcher {
    let lowerBound: UInt64

    var diagnosticDescription: String { "startsAtLeast(\(lowerBound))" }

    func matches(_ value: ExternalReservation) -> Bool {
        value.start >= lowerBound
    }
}

private func archiveScore(
    source: URL,
    bytes: Data,
    interval: DateInterval,
    locale: Locale,
    timeZone: TimeZone,
    amount: Decimal
) -> Int {
    source.absoluteString.count
        + bytes.count
        + Int(interval.duration)
        + locale.identifier.count
        + timeZone.secondsFromGMT()
        + NSDecimalNumber(decimal: amount).intValue
}

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

    @Test func variadicResilientArgumentsDecodeAsOneCollectionInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let first = ExternalReservation(start: 10, end: 12)
        let second = ExternalReservation(start: 14, end: 18)
        stub.when { $0.tally(Match.equal(first), Match.equal(second)) }
            .then { (reservations: [ExternalReservation]) in
                reservations.reduce(0) { $0 ^ $1.start ^ $1.end }
            }
        stub.when { $0.tally(Match.any(using: first), Match.any(using: second)) }
            .thenReturn(0)

        #expect(
            stub().tally(
                ExternalReservation(start: 10, end: 12),
                ExternalReservation(start: 14, end: 18)
            ) == 10 ^ 12 ^ 14 ^ 18
        )
        #expect(
            stub().tally(
                ExternalReservation(start: 20, end: 24),
                ExternalReservation(start: 30, end: 36)
            ) == 0
        )
    }

    @Test func escapingAutoclosureRequirementsRecordPreboundClosureMatchers() throws {
        let stub = try Stub<any AutoclosureDeliveryLog>()
        let placeholder: () -> String = { "" }
        stub.when {
            let matcher = Match.any(using: placeholder)
            return $0.record(matcher())
        }.thenDoNothing()

        stub().record("delivered")
    }

    @Test func foundationArchiveParametersCalibrateInAnOrdinaryConsumer() throws {
        let stub = try Stub<any FoundationArchiveGateway>()
        stub.when {
            $0.archive(
                source: Match.any(),
                bytes: Match.any(),
                interval: Match.any(),
                locale: Match.any(),
                timeZone: Match.any(),
                amount: Match.any()
            )
        }.then {
            (
                source: URL,
                bytes: Data,
                interval: DateInterval,
                locale: Locale,
                timeZone: TimeZone,
                amount: Decimal
            ) in
            archiveScore(
                source: source,
                bytes: bytes,
                interval: interval,
                locale: locale,
                timeZone: timeZone,
                amount: amount
            )
        }

        let actualSource = URL(string: "https://example.com/archive")!
        let actualBytes = Data([4, 5, 6, 7])
        let actualInterval = DateInterval(
            start: Date(timeIntervalSinceReferenceDate: 30),
            duration: 40
        )
        let actualLocale = Locale(identifier: "hu_HU")
        let actualTimeZone = try #require(TimeZone(secondsFromGMT: 3_600))
        let actualAmount = Decimal(11)
        #expect(
            stub().archive(
                source: actualSource,
                bytes: actualBytes,
                interval: actualInterval,
                locale: actualLocale,
                timeZone: actualTimeZone,
                amount: actualAmount
            )
                == archiveScore(
                    source: actualSource,
                    bytes: actualBytes,
                    interval: actualInterval,
                    locale: actualLocale,
                    timeZone: actualTimeZone,
                    amount: actualAmount
                )
        )
    }

    @Test func defaultMatchersCalibrateResilientOptionalArguments() throws {
        let stub = try Stub<any DeliveryGateway>()
        stub.when { $0.review(Match.any()) }.then {
            (reservation: ExternalReservation?) in
            guard let reservation else { return 0 }
            return reservation.start ^ reservation.end
        }

        #expect(
            stub().review(ExternalReservation(start: 17, end: 23)) == 17 ^ 23
        )
        #expect(stub().review(nil) == 0)
    }

    @Test func nestedOptionalMatchersRetainTheirConcretePlaceholderShape() throws {
        let doubleOptionalStub = try Stub<any OptionalDestinationGateway>()
        let doubleOptionalPlaceholder: URL? = URL(
            string: "https://example.com/double-placeholder"
        )
        doubleOptionalStub.when {
            $0.deliver(Match.any(using: doubleOptionalPlaceholder))
        }.then { (destination: URL??) in
            guard case .some(.some(let destination)) = destination else { return 0 }
            return destination.absoluteString.count
        }

        let doubleOptionalActual: URL?? = .some(
            .some(
                URL(string: "https://example.com/double-actual")!
            ))
        #expect(
            doubleOptionalStub().deliver(doubleOptionalActual)
                == "https://example.com/double-actual".count
        )

        let tripleOptionalStub = try Stub<any OptionalDestinationGateway>()
        let tripleOptionalPlaceholder: URL?? = .some(
            .some(
                URL(string: "https://example.com/triple-placeholder")!
            ))
        tripleOptionalStub.when {
            $0.cascade(Match.any(using: tripleOptionalPlaceholder))
        }.then { (destination: URL???) in
            guard case .some(.some(.some(let destination))) = destination
            else {
                return 0
            }
            return destination.absoluteString.count
        }

        let tripleOptionalActual: URL??? = .some(
            .some(
                .some(
                    URL(string: "https://example.com/triple-actual")!
                )))
        #expect(
            tripleOptionalStub().cascade(tripleOptionalActual)
                == "https://example.com/triple-actual".count
        )
    }

    @Test func mixedResilientTupleArgumentsFailBeforeRecording() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any MixedTupleGateway>()
        }
        #expect(error?.description.contains("Tuple members are lowered independently") == true)
        #expect(error?.description.contains("hand-written test double") == true)
    }

    @Test func escapingAutoclosureRequirementsIgnoreXKFInAnIdentifier() throws {
        let stub = try Stub<any XKFAutoclosureDeliveryLog>()
        let placeholder: () -> String = { "" }
        stub.when {
            let matcher = Match.any(using: placeholder)
            return $0.record(matcher())
        }.thenDoNothing()

        stub().record("delivered")
    }

    @Test func signatureOfFunctionValuesExplainTheTypedAdapterBoundary() throws {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any AutoclosureDeliveryLog>(
                .method(signatureOf: (any AutoclosureDeliveryLog).record)
            )
        }
        #expect(error?.description.contains("compiler-typed `using:` adapter") == true)
    }

    @Test func nonescapingAutoclosureRequirementsFailBeforeRecording() throws {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any EagerAutoclosureDeliveryLog>()
        }
        #expect(error?.description.contains("nonescaping @autoclosure") == true)
        #expect(error?.description.contains("ManualStub") == true)
    }

    @Test func nonescapingIntegerAutoclosureRequirementsFailBeforeRecording() throws {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any EagerIntegerAutoclosureDeliveryLog>()
        }
        #expect(error?.description.contains("nonescaping @autoclosure") == true)
        #expect(error?.description.contains("ManualStub") == true)
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

    @Test func partialRangesCalibrateThroughTheGenericMetadataResolver() throws {
        let stub = try Stub<any DeliveryGateway>()
        let after = ExternalReservation(start: 10, end: 12)...
        let through = ...ExternalReservation(start: 20, end: 24)
        let before = ..<ExternalReservation(start: 30, end: 36)

        stub.when {
            $0.classify(
                after: Match.any(using: after),
                through: Match.any(using: through),
                before: Match.any(using: before)
            )
        }.then {
            (
                after: PartialRangeFrom<ExternalReservation>,
                through: PartialRangeThrough<ExternalReservation>,
                before: PartialRangeUpTo<ExternalReservation>
            ) in
            after.lowerBound.start ^ through.upperBound.end ^ before.upperBound.start
        }

        let actualAfter = ExternalReservation(start: 40, end: 44)...
        let actualThrough = ...ExternalReservation(start: 50, end: 56)
        let actualBefore = ..<ExternalReservation(start: 60, end: 68)
        #expect(
            stub().classify(
                after: actualAfter,
                through: actualThrough,
                before: actualBefore
            ) == 40 ^ 56 ^ 60
        )
    }

    @Test func referenceBackedCollectionsStayDirectInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let urls = [
            URL(string: "https://example.com/first")!,
            URL(string: "https://example.com/second")!
        ]
        let reservations = [
            "first": ExternalReservation(start: 10, end: 12),
            "second": ExternalReservation(start: 20, end: 24)
        ]
        stub.when {
            $0.importBatch(
                urls: Match.any(using: urls),
                reservations: Match.any(using: reservations)
            )
        }.then { (urls: [URL], reservations: [String: ExternalReservation]) in
            urls.count
                + reservations.values.reduce(0) { partial, reservation in
                    partial + Int(reservation.start ^ reservation.end)
                }
        }

        let actualURLs = [URL(string: "https://example.com/actual")!]
        let actualReservations = [
            "actual": ExternalReservation(start: 30, end: 36)
        ]
        #expect(stub().importBatch(urls: actualURLs, reservations: actualReservations) == 59)
    }

    @Test func opaqueStandardLibraryGenericArgumentsCalibrateInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        stub.when { $0.sum(Match.any()) }
            .then { (values: ArraySlice<Int>) in values.reduce(0, +) }

        #expect(stub().sum([3, 5, 8][...]) == 16)
    }

    @Test func staticResilientArgumentsCalibrateAfterTheMetatypePayload() throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder = ExternalReservation(start: 70, end: 76)
        stub.when { type(of: $0).tier(Match.any(using: placeholder)) }
            .then { (reservation: ExternalReservation) in
                reservation.start ^ reservation.end
            }

        let value: any DeliveryGateway = stub()
        #expect(
            type(of: value).tier(ExternalReservation(start: 80, end: 88))
                == 8
        )
    }

    @MainActor
    @Test func mainActorResilientArgumentsCalibrateInAnOrdinaryConsumer() throws {
        let stub = try Stub<any MainActorReservationGateway>()
        let placeholder = ExternalReservation(start: 89, end: 97)
        stub.when { $0.review(Match.any(using: placeholder)) }
            .then { (reservation: ExternalReservation) in
                reservation.start ^ reservation.end
            }

        let gateway: any MainActorReservationGateway = stub()
        #expect(gateway.review(ExternalReservation(start: 101, end: 103)) == 2)
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

    @Test func composedOptionalMatchersCalibrateResilientArguments() throws {
        let stub = try Stub<any DeliveryGateway>()
        let excluded = ExternalReservation(start: 43, end: 47)
        stub.when {
            $0.review(Match.some(Match.not(Match.equal(excluded))))
        }.then { (reservation: ExternalReservation?) in
            guard let reservation else { return 0 }
            return reservation.start ^ reservation.end
        }

        let actual = ExternalReservation(start: 53, end: 59)
        #expect(stub().review(actual) == 53 ^ 59)
    }

    @Test func customMatchersCalibrateResilientArgumentsInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder = ExternalReservation(start: 61, end: 67)
        stub.when {
            $0.review(
                Match.custom(
                    using: placeholder,
                    ReservationStartingAtLeast(lowerBound: 60)
                )
            )
        }.then { (reservation: ExternalReservation?) in
            guard let reservation else { return 0 }
            return reservation.start ^ reservation.end
        }
        stub.when { $0.review(Match.any(using: placeholder)) }.thenReturn(0)

        #expect(
            stub().review(ExternalReservation(start: 71, end: 73))
                == 71 ^ 73
        )
        #expect(stub().review(ExternalReservation(start: 59, end: 61)) == 0)
    }

    @Test func capturesCalibrateOptionalResilientArgumentsInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let capture = Match.Capture<ExternalReservation?>()
        let placeholder: ExternalReservation? = ExternalReservation(start: 79, end: 83)
        stub.when { $0.review(capture.capture(using: placeholder)) }
            .then { (reservation: ExternalReservation?) in
                guard let reservation else { return 0 }
                return reservation.start ^ reservation.end
            }

        let actual = ExternalReservation(start: 89, end: 97)
        #expect(stub().review(actual) == 89 ^ 97)
        #expect(stub().review(nil) == 0)
        #expect(capture.values == [actual, nil])
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
        resultStub.when { $0.resolve(Match.any()) }
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
        outcomeStub.when { $0.resolveOutcome(Match.any()) }
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

    @Test func recursiveGenericValuesCalibrateInAnOrdinaryConsumer() throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder: ReservationTree<ExternalReservation> = .child(
            .value(ExternalReservation(start: 113, end: 127))
        )
        stub.when { $0.inspect(Match.any(using: placeholder)) }
            .then { (value: ReservationTree<ExternalReservation>) in
                switch value {
                    case .value(let reservation):
                        return Int(reservation.start ^ reservation.end)
                    case .child(.value(let reservation)):
                        return Int(reservation.start ^ reservation.end)
                    case .child(.child):
                        return -1
                }
            }

        let actual: ReservationTree<ExternalReservation> = .child(
            .value(ExternalReservation(start: 137, end: 139))
        )
        #expect(stub().inspect(actual) == 137 ^ 139)
    }

    @Test func asyncResilientGenericShellCalibratesInAnOrdinaryConsumer() async throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder: ReservationBox<(ExternalReservation, UInt64)> =
            ReservationBox((ExternalReservation(start: 113, end: 127), 131))
        await stub.when {
            await $0.reserve(
                Match.any(using: placeholder),
                marker: Match.any()
            )
        }.then { (value: ReservationBox<(ExternalReservation, UInt64)>, marker: UInt64) async in
            Int(value.value.0.start ^ value.value.0.end ^ value.value.1 ^ marker)
        }

        let actual: ReservationBox<(ExternalReservation, UInt64)> =
            ReservationBox((ExternalReservation(start: 137, end: 139), 149))
        #expect(await stub().reserve(actual, marker: 151) == 137 ^ 139 ^ 149 ^ 151)
    }

    @Test func asyncThrowingResilientArgumentsCalibrateInAnOrdinaryConsumer() async throws {
        let stub = try Stub<any DeliveryGateway>()
        let placeholder = ExternalReservation(start: 157, end: 163)
        await stub.when {
            try await $0.confirm(Match.any(using: placeholder))
        }.then { (reservation: ExternalReservation) async throws in
            reservation.start ^ reservation.end
        }

        #expect(
            try await stub().confirm(ExternalReservation(start: 167, end: 173))
                == 167 ^ 173
        )
    }

    @Test func uncertainImportedResultsFailBeforeInvocation() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ReservationSource>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
    }

    @Test func resilientPropertyResultsFailBeforeASetterCanBeConfigured() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any ReservationStore>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
    }

    @Test func resilientInitializerArgumentsCalibrateInAnOrdinaryConsumer() throws {
        let stub = try Stub<any ReservationSession>()
        stub.when(initializer: {
            type(of: $0).init(
                seed: Match.any(
                    using: ExternalReservation(start: 90, end: 96)
                )
            )
        }).thenInitialize()
        stub.when { $0.identifier() }.thenReturn(101)

        let seed: any ReservationSession = stub()
        let session = type(of: seed).init(
            seed: ExternalReservation(start: 100, end: 108)
        )
        #expect(session.identifier() == 101)
    }

    @Test func asyncResilientInitializerArgumentsCalibrateInAnOrdinaryConsumer() async throws {
        let stub = try Stub<any AsyncReservationSession>()
        await stub.when(initializer: {
            try await type(of: $0).init(
                seed: Match.any(
                    using: ExternalReservation(start: 110, end: 116)
                )
            )
        }).thenInitialize()
        stub.when { $0.identifier() }.thenReturn(121)

        let seed: any AsyncReservationSession = stub()
        let session = try await type(of: seed).init(
            seed: ExternalReservation(start: 120, end: 128)
        )
        #expect(session.identifier() == 121)
    }
}
