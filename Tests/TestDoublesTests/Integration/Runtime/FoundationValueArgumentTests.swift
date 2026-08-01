import Foundation
import Testing
import TestDoubles

enum FoundationValueArgumentError: Error {
    case unavailable
}

protocol FoundationValueProbe {
    func data(_ value: Data) -> Int
    func date(_ value: Date) -> Double
    func dateRange(_ value: ClosedRange<Date>) -> TimeInterval
    func openDateRange(_ value: Range<Date>) -> TimeInterval
    func optionalURL(_ value: URL?) -> Int
    func nestedOptionalURL(_ value: URL??) -> Int
    func optionalURLAsync(_ value: URL?) async -> Int
    func uuid(_ value: UUID) -> String
    func indexPath(_ value: IndexPath) -> Int
}

struct LiveFoundationValueProbe: FoundationValueProbe {
    func data(_ value: Data) -> Int { 0 }
    func date(_ value: Date) -> Double { 0 }
    func dateRange(_ value: ClosedRange<Date>) -> TimeInterval { 0 }
    func openDateRange(_ value: Range<Date>) -> TimeInterval { 0 }
    func optionalURL(_ value: URL?) -> Int { 0 }
    func nestedOptionalURL(_ value: URL??) -> Int { 0 }
    func optionalURLAsync(_ value: URL?) async -> Int { 0 }
    func uuid(_ value: UUID) -> String { "" }
    func indexPath(_ value: IndexPath) -> Int { 0 }
}

/// Values a client passes indirectly because the SDK does not freeze them.
protocol ReferenceBackedFoundationProbe {
    func decimal(_ value: Decimal) -> String
    func url(_ value: URL) -> String
    func calendar(_ value: Calendar) -> String
    func locale(_ value: Locale) -> String
    func timeZone(_ value: TimeZone) -> String
    func indexSet(_ value: IndexSet) -> Int
    func dateInterval(_ value: DateInterval) -> Int
    func measurement(_ value: Measurement<UnitLength>) -> Int
    func route(
        in window: ClosedRange<Date>,
        to endpoint: URL,
        with baggage: Data
    ) -> Int
    func result(_ value: Result<URL, FoundationValueArgumentError>) -> Int
    func linkedResources() -> [URL]
}

struct LiveReferenceBackedFoundationProbe: ReferenceBackedFoundationProbe {
    func decimal(_ value: Decimal) -> String { "" }
    func url(_ value: URL) -> String { "" }
    func calendar(_ value: Calendar) -> String { "" }
    func locale(_ value: Locale) -> String { "" }
    func timeZone(_ value: TimeZone) -> String { "" }
    func indexSet(_ value: IndexSet) -> Int { 0 }
    func dateInterval(_ value: DateInterval) -> Int { 0 }
    func measurement(_ value: Measurement<UnitLength>) -> Int { 0 }
    func route(
        in window: ClosedRange<Date>,
        to endpoint: URL,
        with baggage: Data
    ) -> Int { 0 }
    func result(_: Result<URL, FoundationValueArgumentError>) -> Int { 0 }
    func linkedResources() -> [URL] { [] }
}

/// Foundation value types are the arguments test authors reach for first, and
/// their layouts cover the packed, mixed, and reference-backed shapes at once.
@Suite struct FoundationValueArgumentTests {
    @Test func dataArgument() throws {
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.data(Match.any()) }.then { (value: Data) in value.count }

        #expect(stub().data(Data([1, 2, 3])) == 3)
    }

    @Test func dateArgument() throws {
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.date(Match.any()) }.then { (value: Date) in value.timeIntervalSince1970 }

        #expect(stub().date(Date(timeIntervalSince1970: 5)) == 5)
    }

    @Test func rangeWithAResilientBoundUsesCalibratedIndirectTransport() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let range = start ... Date(timeIntervalSince1970: 1_700_086_400)
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.dateRange(Match.any(using: range)) }
            .then { (value: ClosedRange<Date>) in
                value.upperBound.timeIntervalSince(value.lowerBound)
            }

        #expect(stub().dateRange(range) == 86_400)
    }

    @Test func openRangeWithAResilientBoundUsesCalibratedIndirectTransport() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let range = start ..< Date(timeIntervalSince1970: 1_700_086_400)
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.openDateRange(Match.any(using: range)) }
            .then { (value: Range<Date>) in
                value.upperBound.timeIntervalSince(value.lowerBound)
            }

        #expect(stub().openDateRange(range) == 86_400)
    }

    @Test func optionalResilientValueUsesTheNaturalMatcherSpelling() throws {
        let address = URL(filePath: "/optional")
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.optionalURL(Match.any(using: address)) }
            .then { (value: URL?) in value?.path().count ?? 0 }

        #expect(stub().optionalURL(address) == 9)
    }

    @Test func nestedOptionalResilientValueUsesTheNaturalMatcherSpelling() throws {
        let address = URL(filePath: "/nested-optional")
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.nestedOptionalURL(Match.any(using: address)) }
            .then { (value: URL??) in value??.path().count ?? 0 }

        #expect(stub().nestedOptionalURL(.some(.some(address))) == 16)
    }

    @Test func asyncOptionalResilientValueUsesTheNaturalMatcherSpelling() async throws {
        let address = URL(filePath: "/async-optional")
        let stub = try Stub<any FoundationValueProbe>()
        await stub.when { await $0.optionalURLAsync(Match.any(using: address)) }
            .then { (value: URL?) async in value?.path().count ?? 0 }

        #expect(await stub().optionalURLAsync(address) == 15)
    }

    @Test func uuidArgument() throws {
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.uuid(Match.any()) }.then { (value: UUID) in value.uuidString }

        let identifier = UUID()
        #expect(stub().uuid(identifier) == identifier.uuidString)
    }

    @Test func indexPathArgument() throws {
        let stub = try Stub<any FoundationValueProbe>()
        stub.when { $0.indexPath(Match.any(using: IndexPath())) }
            .then { (value: IndexPath) in value.count }

        #expect(stub().indexPath(IndexPath(indexes: [1, 2])) == 2)
    }

    @Test func decimalArgument() throws {
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.decimal(Match.any()) }.then { (value: Decimal) in "\(value)" }

        #expect(stub().decimal(Decimal(42)) == "42")
        stub.verify { $0.decimal(Match.equal(Decimal(42))) }
    }

    @Test func urlArgument() throws {
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.url(Match.any(using: URL(filePath: "/"))) }.then { (value: URL) in value.path() }

        #expect(stub().url(URL(filePath: "/tmp")) == "/tmp")
    }

    @Test func calendarArgument() throws {
        let calendar = Calendar(identifier: .gregorian)
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.calendar(Match.any(using: calendar)) }
            .then { (value: Calendar) in "\(value.identifier)" }

        #expect(stub().calendar(calendar) == "gregorian")
    }

    @Test func localeAndTimeZoneArguments() throws {
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.locale(Match.any(using: Locale(identifier: "en_US"))) }
            .then { (value: Locale) in value.identifier }
        stub.when { $0.timeZone(Match.any(using: TimeZone(identifier: "UTC")!)) }
            .then { (value: TimeZone) in value.identifier }

        let sut = stub()
        #expect(sut.locale(Locale(identifier: "en_US")) == "en_US")
        #expect(sut.timeZone(TimeZone(identifier: "UTC")!) == "GMT")
    }

    @Test func collectionAndUnitArguments() throws {
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.indexSet(Match.any(using: IndexSet())) }.then { (value: IndexSet) in value.count }
        stub.when { $0.dateInterval(Match.any(using: DateInterval())) }
            .then { (value: DateInterval) in Int(value.duration) }
        stub.when { $0.measurement(Match.any(using: Measurement(value: 0, unit: UnitLength.meters))) }
            .then { (value: Measurement<UnitLength>) in Int(value.value) }

        let sut = stub()
        #expect(sut.indexSet(IndexSet(integersIn: 0 ..< 3)) == 3)
        #expect(sut.dateInterval(DateInterval(start: Date(timeIntervalSince1970: 0), duration: 5)) == 5)
        #expect(sut.measurement(Measurement(value: 7, unit: UnitLength.meters)) == 7)
    }

    @Test func calibratesSeveralResilientArgumentsAsOneCallFrame() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let range = start ... Date(timeIntervalSince1970: 1_700_086_400)
        let endpoint = URL(filePath: "/api/route")
        let baggage = Data([1, 2, 3])
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when {
            $0.route(
                in: Match.any(using: range),
                to: Match.any(using: endpoint),
                with: Match.any(using: baggage)
            )
        }.then { (window: ClosedRange<Date>, url: URL, data: Data) in
            Int(window.upperBound.timeIntervalSince(window.lowerBound))
                + url.path().count
                + data.count
        }

        #expect(stub().route(in: range, to: endpoint, with: baggage) == 86_413)
    }

    @Test func fixedLayoutCollectionResultRemainsSupported() throws {
        let expected = [URL(filePath: "/news/today")]
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.linkedResources() }.thenReturn(expected)

        #expect(stub().linkedResources() == expected)
    }

    @Test func resultWithAResilientPayloadUsesCalibratedIndirectTransport() throws {
        let expected: Result<URL, FoundationValueArgumentError> = .success(
            URL(filePath: "/result")
        )
        let stub = try Stub<any ReferenceBackedFoundationProbe>()
        stub.when { $0.result(Match.any(using: expected)) }
            .then { (value: Result<URL, FoundationValueArgumentError>) in
                switch value {
                    case .success(let address): return address.path().count
                    case .failure: return -1
                }
            }

        #expect(stub().result(expected) == 7)
    }

}
