import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(Dispatch)
    import Dispatch
#endif
#if canImport(Combine)
    import Combine
#endif
import Testing
import TestDoubles

protocol FoundationPlaceholderArgumentProbe {
    #if canImport(Darwin) || canImport(FoundationNetworking)
        func request(_ value: URLRequest) -> String
    #endif
    func name(_ value: Notification.Name) -> String
    func notification(_ value: Notification) -> String
    func attributed(_ value: AttributedString) -> String
    func person(_ value: PersonNameComponents) -> String
    func measurement(_ value: Measurement<UnitLength>) -> Double
}

struct LiveFoundationPlaceholderArgumentProbe: FoundationPlaceholderArgumentProbe {
    #if canImport(Darwin) || canImport(FoundationNetworking)
        func request(_ value: URLRequest) -> String { "" }
    #endif
    func name(_ value: Notification.Name) -> String { "" }
    func notification(_ value: Notification) -> String { "" }
    func attributed(_ value: AttributedString) -> String { "" }
    func person(_ value: PersonNameComponents) -> String { "" }
    func measurement(_ value: Measurement<UnitLength>) -> Double { 0 }
}

struct FoundationPlaceholderArgumentTests {
    #if canImport(Darwin) || canImport(FoundationNetworking)
        @Test func urlRequestRecordsWithoutAFixture() throws {
            let stub = try makeFoundationPlaceholderArgumentStub()
            stub.when { $0.request(Match.any()) }
                .then { (value: URLRequest) in value.url?.absoluteString ?? "" }

            let request = URLRequest(url: URL(string: "https://example.com")!)
            #expect(stub().request(request) == "https://example.com")
        }
    #endif

    @Test func foundationValuesRecordWithoutFixtures() throws {
        let stub = try makeFoundationPlaceholderArgumentStub()
        stub.when { $0.name(Match.any()) }
            .then { (value: Notification.Name) in value.rawValue }
        stub.when { $0.notification(Match.any()) }
            .then { (value: Notification) in value.name.rawValue }
        stub.when { $0.attributed(Match.any()) }
            .then { (value: AttributedString) in String(value.characters) }
        stub.when { $0.person(Match.any()) }
            .then { (value: PersonNameComponents) in value.givenName ?? "" }
        stub.when { $0.measurement(Match.any()) }
            .then { (value: Measurement<UnitLength>) in
                value.converted(to: .meters).value
            }

        var person = PersonNameComponents()
        person.givenName = "Blob"
        #expect(stub().name(Notification.Name("event")) == "event")
        #expect(stub().notification(Notification(name: .init("posted"))) == "posted")
        #expect(stub().attributed(AttributedString("styled")) == "styled")
        #expect(stub().person(person) == "Blob")
        #expect(stub().measurement(Measurement(value: 3, unit: .meters)) == 3)
    }
}

private func makeFoundationPlaceholderArgumentStub() throws
    -> Stub<any FoundationPlaceholderArgumentProbe>
{
    try Stub()
}

#if canImport(Dispatch)
    protocol DispatchPlaceholderArgumentProbe {
        func data(_ value: DispatchData) -> Int
        func queue(_ value: DispatchQueue) -> String
    }

    struct LiveDispatchPlaceholderArgumentProbe: DispatchPlaceholderArgumentProbe {
        func data(_ value: DispatchData) -> Int { 0 }
        func queue(_ value: DispatchQueue) -> String { "" }
    }

    struct DispatchPlaceholderArgumentTests {
        @Test func dispatchValuesRecordWithoutFixtures() throws {
            let stub = try Stub<any DispatchPlaceholderArgumentProbe>()
            stub.when { $0.data(Match.any()) }
                .then { (value: DispatchData) in value.count }
            stub.when { $0.queue(Match.any()) }
                .then { (value: DispatchQueue) in value.label }

            let bytes: [UInt8] = [1, 2, 3]
            let data = bytes.withUnsafeBytes { DispatchData(bytes: $0) }
            let queue = DispatchQueue(label: "test-doubles.actual")
            #expect(stub().data(data) == 3)
            #expect(stub().queue(queue) == "test-doubles.actual")
        }
    }
#endif

#if canImport(Combine)
    protocol CombinePlaceholderArgumentProbe {
        func subscription(_ value: any Subscription) -> Int
        func publisher(_ value: AnyPublisher<Int, Never>) -> Int
        func subscriber(_ value: AnySubscriber<Int, Never>) -> Int
        func cancellable(_ value: AnyCancellable) -> Int
        func passthrough(_ value: PassthroughSubject<Int, Never>) -> Int
        func current(_ value: CurrentValueSubject<Int, Never>) -> Int
    }

    struct LiveCombinePlaceholderArgumentProbe: CombinePlaceholderArgumentProbe {
        func subscription(_ value: any Subscription) -> Int { 0 }
        func publisher(_ value: AnyPublisher<Int, Never>) -> Int { 0 }
        func subscriber(_ value: AnySubscriber<Int, Never>) -> Int { 0 }
        func cancellable(_ value: AnyCancellable) -> Int { 0 }
        func passthrough(_ value: PassthroughSubject<Int, Never>) -> Int { 0 }
        func current(_ value: CurrentValueSubject<Int, Never>) -> Int { 0 }
    }

    struct CombinePlaceholderArgumentTests {
        @Test func combineValuesRecordWithoutFixtures() throws {
            let stub = try Stub<any CombinePlaceholderArgumentProbe>()
            stub.when { $0.subscription(Match.any()) }.thenReturn(1)
            stub.when { $0.publisher(Match.any()) }.thenReturn(2)
            stub.when { $0.subscriber(Match.any()) }.thenReturn(3)
            stub.when { $0.cancellable(Match.any()) }.thenReturn(4)
            stub.when { $0.passthrough(Match.any()) }.thenReturn(5)
            stub.when { $0.current(Match.any()) }
                .then { (value: CurrentValueSubject<Int, Never>) in value.value }

            let subscriber = AnySubscriber<Int, Never>(
                receiveSubscription: { _ in },
                receiveValue: { _ in .none },
                receiveCompletion: { _ in }
            )
            #expect(stub().subscription(Subscriptions.empty) == 1)
            #expect(stub().publisher(Empty().eraseToAnyPublisher()) == 2)
            #expect(stub().subscriber(subscriber) == 3)
            #expect(stub().cancellable(AnyCancellable {}) == 4)
            #expect(stub().passthrough(PassthroughSubject()) == 5)
            #expect(stub().current(CurrentValueSubject(42)) == 42)
        }
    }
#endif
