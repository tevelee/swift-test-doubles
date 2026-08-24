import ConsumerFixtures
import TestDoubles
import Testing

@Suite struct CompilerSmokeConsumerTests {
    @Test func importedProtocolSupportsConfigurationAndVerification() throws {
        let stub = try Stub<any RuntimeConsumerSmokeService>()
        let call = stub.when { $0.value(for: Match.equal(7)) }.thenReturn(42)

        #expect(stub().value(for: 7) == 42)
        call.verify()
    }
}
