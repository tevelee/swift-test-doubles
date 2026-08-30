import ConsumerFixtures
import Foundation
#if canImport(FoundationNetworking) && !os(Android)
    import FoundationNetworking
#endif
import TestDoubles
import Testing

@Suite struct BuiltInFoundationResultConsumerTests {
    @Test func automaticConstructionTransportsThrowingDataResultWithArgument() throws {
        struct Failure: Error {}

        let stub = try Stub<any ImportedPathDataSource>()
        let expected = Data([191, 193, 197])
        stub.when { try $0.read(path: "/fixture") }.thenReturn(expected)
        stub.when { try $0.read(path: Match.any()) }.thenThrow(Failure())

        let source = stub()
        #expect(throws: Failure.self) {
            try source.read(path: "/missing")
        }
        #expect(try source.read(path: "/fixture") == expected)
        stub.verify(2 ... 2) { try $0.read(path: Match.any()) }
    }

    @Test func automaticConstructionTransportsCommonAsyncThrowingDataResult() async throws {
        let stub = try Stub<any ImportedDataSource>()
        let expected = Data([197, 199, 211])
        await stub.when(returning: expected) {
            try await $0.loadData()
        }.thenReturn(expected)

        let source = stub()
        #expect(try await source.loadData() == expected)
        let executed = try await execute(with: source)
        #expect(executed == expected)
        await stub.verify(2 ... 2, returning: expected) { try await $0.loadData() }
    }

    #if compiler(>=6.4)
        @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
        @Test func automaticConstructionAdaptsCommonFoundationResultEffects() async throws {
            let stub = try Stub<any CommonFoundationResultSource>()
            let expectedURL = URL(filePath: "/fixture")
            let expectedData = Data([223, 227])
            let expectedDate = Date(timeIntervalSinceReferenceDate: 229)
            let expectedIdentifier = UUID(
                uuidString: "00000000-0000-0000-0000-000000000233"
            )!
            let expectedInterval = DateInterval(start: expectedDate, duration: 239)
            let expectedCalendar = Calendar(identifier: .iso8601)
            let expectedLocale = Locale(identifier: "en_GB")
            let expectedTimeZone = try #require(TimeZone(secondsFromGMT: 3_600))
            let expectedIndexPath = IndexPath(indexes: [2, 3, 5])
            let expectedIndexSet = IndexSet([7, 11, 13])
            let expectedCharacterSet = CharacterSet(charactersIn: "abc")
            let expectedDecimal = Decimal(251)
            let expectedNotificationName = Notification.Name("fixture")
            let expectedNotification = Notification(name: expectedNotificationName)
            let expectedAttributedString = AttributedString("fixture")
            var expectedPersonName = PersonNameComponents()
            expectedPersonName.givenName = "Test"
            expectedPersonName.familyName = "Doubles"
            #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
                let expectedRequest = URLRequest(url: expectedURL)
            #endif

            stub.when(returning: expectedURL) { $0.currentURL }.thenReturn(expectedURL)
            stub.when(returning: expectedData) { $0.data() }.thenReturn(expectedData)
            stub.when(returning: expectedDate) { try $0.date() }.thenReturn(expectedDate)
            await stub.when(returning: expectedIdentifier) {
                await $0.identifier()
            }.thenReturn(expectedIdentifier)
            await stub.when(returning: expectedInterval) {
                try await $0.interval()
            }.thenReturn(expectedInterval)
            await stub.when(returning: expectedCalendar) {
                try await $0.calendar()
            }.thenReturn(expectedCalendar)
            stub.when(returning: expectedLocale) { $0.locale() }.thenReturn(expectedLocale)
            stub.when(returning: expectedTimeZone) { try $0.timeZone() }
                .thenReturn(expectedTimeZone)
            await stub.when(returning: expectedIndexPath) { await $0.indexPath() }
                .thenReturn(expectedIndexPath)
            await stub.when(returning: expectedIndexSet) { try await $0.indexSet() }
                .thenReturn(expectedIndexSet)
            stub.when(returning: expectedCharacterSet) { $0.characterSet() }
                .thenReturn(expectedCharacterSet)
            stub.when(returning: expectedDecimal) { try $0.decimal() }
                .thenReturn(expectedDecimal)
            await stub.when(returning: expectedNotificationName) {
                await $0.notificationName()
            }.thenReturn(expectedNotificationName)
            await stub.when(returning: expectedNotification) {
                try await $0.notification()
            }.thenReturn(expectedNotification)
            stub.when(returning: expectedAttributedString) { $0.attributedString() }
                .thenReturn(expectedAttributedString)
            await stub.when(returning: expectedPersonName) {
                try await $0.personNameComponents()
            }.thenReturn(expectedPersonName)
            #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
                await stub.when(returning: expectedRequest) {
                    try await $0.request()
                }.thenReturn(expectedRequest)
            #endif

            #expect(stub().currentURL == expectedURL)
            #expect(stub().data() == expectedData)
            #expect(try stub().date() == expectedDate)
            #expect(await stub().identifier() == expectedIdentifier)
            #expect(try await stub().interval() == expectedInterval)
            #expect(try await stub().calendar() == expectedCalendar)
            #expect(stub().locale() == expectedLocale)
            #expect(try stub().timeZone() == expectedTimeZone)
            #expect(await stub().indexPath() == expectedIndexPath)
            #expect(try await stub().indexSet() == expectedIndexSet)
            #expect(stub().characterSet() == expectedCharacterSet)
            #expect(try stub().decimal() == expectedDecimal)
            #expect(await stub().notificationName() == expectedNotificationName)
            #expect(try await stub().notification().name == expectedNotificationName)
            #expect(stub().attributedString() == expectedAttributedString)
            #expect(try await stub().personNameComponents() == expectedPersonName)
            #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
                #expect(try await stub().request() == expectedRequest)
            #endif
        }
    #endif

    #if compiler(>=6.4)
        @Test func automaticConstructionTransportsAsyncUUIDResultWithArgument() async throws {
            let stub = try Stub<any ParameterizedFoundationResultSource>()
            let expected = UUID(
                uuidString: "00000000-0000-0000-0000-000000000257"
            )!
            await stub.when(returning: expected) {
                await $0.identifier(
                    for: Match.equal(257),
                    namespace: Match.equal("fixture")
                )
            }.thenReturn(expected)

            #expect(
                await stub().identifier(for: 257, namespace: "fixture")
                    == expected
            )
        }
    #endif

    private func execute(with source: some ImportedDataSource) async throws -> Data {
        try await source.loadData()
    }
}
