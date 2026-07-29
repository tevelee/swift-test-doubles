import TestDoublesResilientFixtures
import Testing
@testable import TestDoubles

struct ResilientProtocolDiscoveryTests {
    @Test func discoversRequirementsWithoutALinkedConformer() async throws {
        let stub = try Stub<any ResilientRuntimeService>()

        stub.onCall { try $0.fetch(id: Match.any()) }.then { (value: Int) in
            "fetched-\(value)"
        }
        await stub.onCall { try await $0.load(id: Match.any()) }.then { (value: Int) async throws in
            if value < 0 { throw ResilientRuntimeError.rejected(value) }
            return "loaded-\(value)"
        }
        stub.onCall { type(of: $0).label(Match.any()) }.then { (value: Int) in
            "label-\(value)"
        }
        stub.onCall(initializer: { type(of: $0).init(id: Match.any()) }).thenInitialize()
        stub.onCall { $0.count }.thenReturn(7)
        stub.onCall { $0.count = Match.any() }.thenDoNothing()

        var value: any ResilientRuntimeService = stub()
        #expect(try value.fetch(id: 1) == "fetched-1")
        #expect(try await value.load(id: 2) == "loaded-2")
        await #expect(throws: ResilientRuntimeError.rejected(-1)) {
            _ = try await value.load(id: -1)
        }
        #expect(type(of: value).label(3) == "label-3")
        #expect(type(of: value).init(id: 4).count == 7)
        value.count = 5

        stub.verify { try $0.fetch(id: Match.equal(1)) }
        await stub.verify { try await $0.load(id: Match.equal(2)) }
        stub.verify { type(of: $0).label(Match.equal(3)) }
        stub.verify { type(of: $0).init(id: Match.equal(4)) }
        stub.verify { $0.count = Match.equal(5) }
    }

    @Test func validatesExplicitRequirementsWithoutALinkedConformer() {
        expectStubError({
            _ = try Stub<any ResilientRuntimeService>(
                .method(Int.self, returning: Int.self, isThrowing: true),
                .method(
                    Int.self,
                    returning: String.self,
                    throwing: ResilientRuntimeError.self,
                    isAsync: true
                ),
                .method(Int.self, returning: String.self),
                .initializer(Int.self),
                .getter(Int.self),
                .setter(Int.self)
            )
        }) { error in
            guard case .requirementMismatch(_, let index, _, _) = error else {
                return false
            }
            return index == 0
        }
    }
}
