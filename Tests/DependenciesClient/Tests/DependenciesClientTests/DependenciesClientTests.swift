import Dependencies
import DependenciesClientFixtures
import DependenciesTestSupport
import Testing

@Suite struct DependenciesClientTests {
    @Test func generatedPresetSuppliesTheDefaultTestDependency() {
        @Dependency(FeatureClient.self) var client

        let _: FeatureClient = client
    }

    @Test(
        .dependencies {
            $0.featureClient = await FeatureClientDoubles.preset.testValue { stub in
                await stub.when { try await $0.fetch(42) }.thenReturn("forty-two")
            }
        }
    )
    func generatedPresetOverridesAKeyPathDependency() async throws {
        @Dependency(\.featureClient) var client

        #expect(try await client.fetch(42) == "forty-two")
    }
}
