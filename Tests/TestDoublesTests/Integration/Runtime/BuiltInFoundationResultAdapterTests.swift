import Foundation
@testable import TestDoubles
import Testing

#if !os(WASI)
    protocol DirectFoundationResultSource {
        func data() -> Data
        func throwingData() throws -> Data
        func asyncData() async -> Data
        func asyncThrowingData() async throws -> Data

        func decimal() -> Decimal
        func throwingDecimal() throws -> Decimal
        func asyncDecimal() async -> Decimal
        func asyncThrowingDecimal() async throws -> Decimal

        func notificationName() -> Notification.Name
        func throwingNotificationName() throws -> Notification.Name
        func asyncNotificationName() async -> Notification.Name
        func asyncThrowingNotificationName() async throws -> Notification.Name
    }

    struct LinkedDirectFoundationResultSource: DirectFoundationResultSource {
        func data() -> Data { Data() }
        func throwingData() throws -> Data { Data() }
        func asyncData() async -> Data { Data() }
        func asyncThrowingData() async throws -> Data { Data() }

        func decimal() -> Decimal { Decimal() }
        func throwingDecimal() throws -> Decimal { Decimal() }
        func asyncDecimal() async -> Decimal { Decimal() }
        func asyncThrowingDecimal() async throws -> Decimal { Decimal() }

        func notificationName() -> Notification.Name { Notification.Name("linked") }
        func throwingNotificationName() throws -> Notification.Name {
            Notification.Name("linked")
        }
        func asyncNotificationName() async -> Notification.Name { Notification.Name("linked") }
        func asyncThrowingNotificationName() async throws -> Notification.Name {
            Notification.Name("linked")
        }
    }

    @Suite struct BuiltInFoundationResultAdapterTests {
        @Test func directFoundationAdaptersCoverEveryEffectShape() async throws {
            _ = LinkedDirectFoundationResultSource()
            let stub = try Stub<any DirectFoundationResultSource>()

            let data = (1 ... 4).map { Data([UInt8($0)]) }
            stub.when { $0.data() }.thenReturn(data[0])
            stub.when { try $0.throwingData() }.thenReturn(data[1])
            await stub.when { await $0.asyncData() }.thenReturn(data[2])
            await stub.when { try await $0.asyncThrowingData() }.thenReturn(data[3])

            let decimals = (5 ... 8).map { Decimal($0) }
            stub.when { $0.decimal() }.thenReturn(decimals[0])
            stub.when { try $0.throwingDecimal() }.thenReturn(decimals[1])
            await stub.when { await $0.asyncDecimal() }.thenReturn(decimals[2])
            await stub.when { try await $0.asyncThrowingDecimal() }.thenReturn(decimals[3])

            let names = (9 ... 12).map { Notification.Name("name-\($0)") }
            stub.when { $0.notificationName() }.thenReturn(names[0])
            stub.when { try $0.throwingNotificationName() }.thenReturn(names[1])
            await stub.when { await $0.asyncNotificationName() }.thenReturn(names[2])
            await stub.when { try await $0.asyncThrowingNotificationName() }
                .thenReturn(names[3])

            let source = stub()
            #expect(source.data() == data[0])
            #expect(try source.throwingData() == data[1])
            #expect(await source.asyncData() == data[2])
            #expect(try await source.asyncThrowingData() == data[3])
            #expect(source.decimal() == decimals[0])
            #expect(try source.throwingDecimal() == decimals[1])
            #expect(await source.asyncDecimal() == decimals[2])
            #expect(try await source.asyncThrowingDecimal() == decimals[3])
            #expect(source.notificationName() == names[0])
            #expect(try source.throwingNotificationName() == names[1])
            #expect(await source.asyncNotificationName() == names[2])
            #expect(try await source.asyncThrowingNotificationName() == names[3])
        }
    }
#endif
