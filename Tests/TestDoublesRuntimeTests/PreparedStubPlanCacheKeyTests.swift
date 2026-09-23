import InternalRuntimeContract
import Testing
@testable import TestDoublesRuntime

private protocol CacheKeyProbe {}

/// Plans are keyed by the identity of the shared adapter set, so a steady
/// construction does not rebuild and hash a key entry for every adapter.
@Suite struct PreparedStubPlanCacheKeyTests {
    private func request(
        adapters: RuntimeAutomaticRequirementAdapterSet
    ) -> RuntimeStubPreparationRequest {
        RuntimeStubPreparationRequest(
            shape: RuntimeProtocolShapeRequest(
                protocolType: (any CacheKeyProbe).self,
                typeDescription: "CacheKeyProbe",
                callerAssociatedTypeBindings: []
            ),
            requirements: .automatic,
            getterEffects: .automatic,
            automaticRequirementAdapters: adapters
        )
    }

    @Test func requestsSharingAnAdapterSetShareAKey() throws {
        let adapters = RuntimeAutomaticRequirementAdapterSet([
            RuntimeAutomaticRequirementAdapter(
                kind: .method,
                resultType: Int.self,
                resultTransport: .direct,
                isThrowing: false,
                isAsync: false
            )
        ])
        let first = try #require(PreparedStubPlanCache.key(for: request(adapters: adapters)))
        let second = try #require(PreparedStubPlanCache.key(for: request(adapters: adapters)))

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test func distinctAdapterSetsNeverShareAKey() throws {
        let first = try #require(
            PreparedStubPlanCache.key(for: request(adapters: RuntimeAutomaticRequirementAdapterSet([])))
        )
        let second = try #require(
            PreparedStubPlanCache.key(for: request(adapters: RuntimeAutomaticRequirementAdapterSet([])))
        )

        #expect(first != second)
    }
}
