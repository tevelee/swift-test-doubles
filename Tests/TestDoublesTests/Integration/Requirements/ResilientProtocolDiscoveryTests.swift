import TestDoublesResilientFixtures
import Testing
@testable import TestDoubles

struct ResilientProtocolDiscoveryTests {
    @Test func discoversRequirementsWithoutALinkedConformer() async throws {
        let stub = try Stub<any ResilientRuntimeService>()

        stub.when { try $0.fetch(id: any()) }.then { (value: Int) in
            "fetched-\(value)"
        }
        await stub.when { try await $0.load(id: any()) }.then { (value: Int) async throws in
            if value < 0 { throw ResilientRuntimeError.rejected(value) }
            return "loaded-\(value)"
        }
        stub.when { type(of: $0).label(any()) }.then { (value: Int) in
            "label-\(value)"
        }
        stub.when(initializer: { type(of: $0).init(id: any()) }).thenInitialize()
        stub.when { $0.count }.thenReturn(7)
        stub.when { $0.count = any() }

        var value: any ResilientRuntimeService = stub()
        #expect(try value.fetch(id: 1) == "fetched-1")
        #expect(try await value.load(id: 2) == "loaded-2")
        await #expect(throws: ResilientRuntimeError.rejected(-1)) {
            _ = try await value.load(id: -1)
        }
        #expect(type(of: value).label(3) == "label-3")
        #expect(type(of: value).init(id: 4).count == 7)
        value.count = 5

        stub.verify { try $0.fetch(id: equal(1)) }
        await stub.verify { try await $0.load(id: equal(2)) }
        stub.verify { type(of: $0).label(equal(3)) }
        stub.verify { type(of: $0).init(id: equal(4)) }
        stub.verify { $0.count = equal(5) }
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
