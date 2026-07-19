import Testing
@testable import TestDoubles

private enum StaticRequirementError: Error, Equatable {
    case rejected(Int)
}

protocol StaticRequirementProbe {
    static func describe(_ value: Int) -> String
    static var count: Int { get set }
    static func load(_ value: Int) async throws -> String
}

struct RealStaticRequirementProbe: StaticRequirementProbe {
    static func describe(_ value: Int) -> String { "real-\(value)" }

    nonisolated(unsafe) static var count: Int {
        get { 0 }
        set {}
    }

    static func load(_ value: Int) async throws -> String { "real-\(value)" }
}

private protocol ExplicitStaticRequirementProbe {
    static func transform(_ value: Int) -> String
}

protocol StaticBaseRequirementProbe {
    static func baseValue() -> Int
}

protocol StaticChildRequirementProbe: StaticBaseRequirementProbe {
    static func childValue() -> Int
}

struct RealStaticChildRequirementProbe: StaticChildRequirementProbe {
    static func baseValue() -> Int { 0 }
    static func childValue() -> Int { 0 }
}

protocol FirstStaticCompositionProbe {
    static func firstValue() -> Int
}

protocol SecondStaticCompositionProbe {
    static func secondValue() -> Int
}

struct RealFirstStaticCompositionProbe: FirstStaticCompositionProbe {
    static func firstValue() -> Int { 0 }
}

struct RealSecondStaticCompositionProbe: SecondStaticCompositionProbe {
    static func secondValue() -> Int { 0 }
}

protocol ClassStaticRequirementProbe: AnyObject {
    static func describe(_ value: Int) throws -> String
    static func load(_ value: Int) async -> String
}

final class RealClassStaticRequirementProbe: ClassStaticRequirementProbe {
    static func describe(_ value: Int) throws -> String { "real-\(value)" }
    static func load(_ value: Int) async -> String { "real-\(value)" }
}

@inline(never)
private func useLinkedStaticRequirement(
    _ value: any StaticRequirementProbe
) -> String {
    type(of: value).describe(0)
}

@inline(never)
private func useLinkedStaticChildRequirement(
    _ value: any StaticChildRequirementProbe
) -> Int {
    type(of: value).baseValue() + type(of: value).childValue()
}

@inline(never)
private func useLinkedFirstStaticComposition(
    _ value: any FirstStaticCompositionProbe
) -> Int {
    type(of: value).firstValue()
}

@inline(never)
private func useLinkedSecondStaticComposition(
    _ value: any SecondStaticCompositionProbe
) -> Int {
    type(of: value).secondValue()
}

struct StaticRequirementTests {
    @Test func automaticDiscoverySupportsStaticMethodsAndProperties() async throws {
        #expect(useLinkedStaticRequirement(RealStaticRequirementProbe()) == "real-0")
        let stub = try Stub<any StaticRequirementProbe>()

        stub.when { type(of: $0).describe(any()) }.then { (value: Int) in
            "stub-\(value)"
        }
        stub.when { type(of: $0).count }.thenReturn(7)
        stub.when { type(of: $0).count = any() }.thenDoNothing()
        await stub.when { try await type(of: $0).load(any()) }.then { value in
            if value < 0 { throw StaticRequirementError.rejected(value) }
            return "loaded-\(value)"
        }

        let value: any StaticRequirementProbe = stub()
        #expect(type(of: value).describe(3) == "stub-3")
        #expect(type(of: value).count == 7)
        type(of: value).count = 11
        #expect(try await type(of: value).load(5) == "loaded-5")
        await #expect(throws: StaticRequirementError.rejected(-1)) {
            _ = try await type(of: value).load(-1)
        }
        #expect(stub.withValue { type(of: $0).describe(9) } == "stub-9")
        #expect(try await stub.withValue { try await type(of: $0).load(10) } == "loaded-10")

        stub.verify { type(of: $0).describe(equal(3)) }
        stub.verify { type(of: $0).count = equal(11) }
        await stub.verify { try await type(of: $0).load(equal(5)) }
    }

    @Test func explicitRequirementsSupportStaticMethodsWithoutAConformer() throws {
        let stub = try Stub<any ExplicitStaticRequirementProbe>(
            .method(Int.self, returning: String.self)
        )
        stub.when { type(of: $0).transform(any()) }.then { (value: Int) in
            "explicit-\(value)"
        }

        let value: any ExplicitStaticRequirementProbe = stub()
        #expect(type(of: value).transform(4) == "explicit-4")
    }

    @Test func aGeneratedValueKeepsStaticRuntimeResourcesAlive() throws {
        var stub: Stub<any ExplicitStaticRequirementProbe>? = try Stub(
            .method(Int.self, returning: String.self)
        )
        stub!.when {
            type(of: $0).transform(any())
        }.then { (value: Int) in
            "alive-\(value)"
        }
        let value: any ExplicitStaticRequirementProbe = stub!()
        weak let weakStub = stub

        stub = nil

        #expect(weakStub == nil)
        #expect(type(of: value).transform(5) == "alive-5")
    }

    @Test func inheritedStaticRequirementsUseTheirDeclaringWitnessTables() throws {
        #expect(useLinkedStaticChildRequirement(RealStaticChildRequirementProbe()) == 0)
        let stub = try Stub<any StaticChildRequirementProbe>()
        stub.when { type(of: $0).baseValue() }.thenReturn(21)
        stub.when { type(of: $0).childValue() }.thenReturn(42)

        let value: any StaticChildRequirementProbe = stub()
        #expect(type(of: value).baseValue() == 21)
        #expect(type(of: value).childValue() == 42)
    }

    @Test func staticRequirementsWorkAcrossProtocolCompositions() throws {
        #expect(useLinkedFirstStaticComposition(RealFirstStaticCompositionProbe()) == 0)
        #expect(useLinkedSecondStaticComposition(RealSecondStaticCompositionProbe()) == 0)
        let stub = try Stub<any FirstStaticCompositionProbe & SecondStaticCompositionProbe>()
        stub.when { type(of: $0).firstValue() }.thenReturn(1)
        stub.when { type(of: $0).secondValue() }.thenReturn(2)

        let value: any FirstStaticCompositionProbe & SecondStaticCompositionProbe = stub()
        #expect(type(of: value).firstValue() == 1)
        #expect(type(of: value).secondValue() == 2)
    }

    @Test func classStaticRequirementsPreserveEffectsAndValueOwnership() async throws {
        var stub: Stub<any ClassStaticRequirementProbe>? = try Stub()
        stub?.when { try type(of: $0).describe(any()) }.then { value in
            if value < 0 { throw StaticRequirementError.rejected(value) }
            return "described-\(value)"
        }
        await stub?.when { await type(of: $0).load(any()) }.then {
            (value: Int) async in
            await Task.yield()
            return "loaded-\(value)"
        }

        var owner = stub
        let value: any ClassStaticRequirementProbe = try #require(owner.map { $0() })
        owner = nil
        stub = nil

        #expect(try type(of: value).describe(6) == "described-6")
        #expect(throws: StaticRequirementError.rejected(-1)) {
            _ = try type(of: value).describe(-1)
        }
        #expect(await type(of: value).load(7) == "loaded-7")
    }
}
