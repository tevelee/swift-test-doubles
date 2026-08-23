import Dependencies
import TestDoubles
import TestDoublesMacros

@StubbableClient
public struct FeatureClient: Sendable {
    public var fetch: @Sendable (Int) async throws -> String

    public init(
        fetch: @escaping @Sendable (Int) async throws -> String
    ) {
        self.fetch = fetch
    }
}

extension FeatureClient: TestDependencyKey {
    public static var testValue: Self {
        FeatureClientDoubles.testValue
    }
}

extension DependencyValues {
    public var featureClient: FeatureClient {
        get { self[FeatureClient.self] }
        set { self[FeatureClient.self] = newValue }
    }
}
