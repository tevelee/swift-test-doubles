import Foundation
import Testing
import TestDoubles

protocol FoundationValueProbe {
    func data(_ value: Data) -> Int
    func date(_ value: Date) -> Double
    func uuid(_ value: UUID) -> String
    func indexPath(_ value: IndexPath) -> Int
}

struct LiveFoundationValueProbe: FoundationValueProbe {
    func data(_ value: Data) -> Int { 0 }
    func date(_ value: Date) -> Double { 0 }
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
}
