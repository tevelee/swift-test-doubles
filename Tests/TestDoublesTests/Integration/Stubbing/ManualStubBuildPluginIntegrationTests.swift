import Testing
import TestDoubles
@testable import ManualStubBuildPluginIntegrationFixtures

@Suite struct ManualStubBuildPluginIntegrationTests {
    @Test func buildPluginGeneratesACompilingManualStub() {
        let stub = BuildGeneratedGreetingServiceStub()
        stub.when { $0.greeting(for: "Ada") }.thenReturn("Hello, Ada")
        stub.when { $0.requestCount }.thenReturn(1)

        let service: any BuildGeneratedGreetingService = stub()

        #expect(service.greeting(for: "Ada") == "Hello, Ada")
        #expect(service.requestCount == 1)
        stub.verify { $0.greeting(for: "Ada") }
        stub.verify { $0.requestCount }
    }

    @Test func generatedEffectfulGettersReturnConfiguredValues() async throws {
        let stub = BuildGeneratedEffectfulGettersStub()
        await stub.when { await $0.asyncValue }.thenReturn(1)
        stub.when { try $0.throwingValue }.thenReturn(2)
        await stub.when { try await $0.asyncThrowingValue }.thenReturn(3)
        stub.when { try $0.typedThrowingValue }.thenReturn(4)
        await stub.when { try await $0.asyncTypedThrowingValue }.thenReturn(5)
        await stub.when { await $0[asynchronous: 10] }.thenReturn(6)
        stub.when { try $0[throwing: 10] }.thenReturn(7)
        await stub.when { try await $0[asyncThrowing: 10] }.thenReturn(8)
        stub.when { try $0[typedThrowing: 10] }.thenReturn(9)
        await stub.when { try await $0[asyncTypedThrowing: 10] }.thenReturn(10)

        let service: any BuildGeneratedEffectfulGetters = stub()
        #expect(await service.asyncValue == 1)
        #expect(try service.throwingValue == 2)
        #expect(try await service.asyncThrowingValue == 3)
        #expect(try service.typedThrowingValue == 4)
        #expect(try await service.asyncTypedThrowingValue == 5)
        #expect(await service[asynchronous: 10] == 6)
        #expect(try service[throwing: 10] == 7)
        #expect(try await service[asyncThrowing: 10] == 8)
        #expect(try service[typedThrowing: 10] == 9)
        #expect(try await service[asyncTypedThrowing: 10] == 10)
    }

    @Test func generatedThrowingGettersPropagateConfiguredErrors() async {
        let stub = BuildGeneratedEffectfulGettersStub()
        stub.when { try $0.throwingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0.asyncThrowingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        stub.when { try $0.typedThrowingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0.asyncTypedThrowingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        stub.when { try $0[throwing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0[asyncThrowing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)
        stub.when { try $0[typedThrowing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0[asyncTypedThrowing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)

        let service: any BuildGeneratedEffectfulGetters = stub()
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service.throwingValue }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service.asyncThrowingValue }
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service.typedThrowingValue }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service.asyncTypedThrowingValue }
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service[throwing: 10] }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service[asyncThrowing: 10] }
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service[typedThrowing: 10] }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service[asyncTypedThrowing: 10] }
    }

}
