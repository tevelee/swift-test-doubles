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
}
