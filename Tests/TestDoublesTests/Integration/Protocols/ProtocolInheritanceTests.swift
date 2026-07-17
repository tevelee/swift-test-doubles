import Testing
@testable import TestDoubles

protocol AutomaticInheritanceBaseProbe {
    func base(_ value: Int) -> String
    var baseValue: Int { get }
}

protocol AutomaticInheritanceChildProbe: AutomaticInheritanceBaseProbe {
    func child() -> Bool
}

struct LinkedAutomaticInheritanceProbe: AutomaticInheritanceChildProbe {
    func base(_ value: Int) -> String { "\(value)" }
    var baseValue: Int { 0 }
    func child() -> Bool { false }
}

private protocol ExplicitInheritanceBaseProbe {
    func base(_ value: Int) -> String
    var baseValue: Int { get }
}

private protocol ExplicitInheritanceChildProbe: ExplicitInheritanceBaseProbe {
    func child() -> Bool
}

protocol DiamondRootProbe {
    func root(_ value: Int) -> String
}

protocol DiamondLeftProbe: DiamondRootProbe {
    func left() -> Int
}

protocol DiamondRightProbe: DiamondRootProbe {
    var right: String { get }
}

protocol DiamondProbe: DiamondLeftProbe, DiamondRightProbe {
    func finish(_ value: Bool) -> Bool
}

struct LinkedDiamondProbe: DiamondProbe {
    func root(_ value: Int) -> String { "\(value)" }
    func left() -> Int { 0 }
    var right: String { "" }
    func finish(_ value: Bool) -> Bool { value }
}

protocol SendableInheritanceProbe: AutomaticInheritanceBaseProbe, Sendable {
    func sendableChild() -> Int
}

struct LinkedSendableInheritanceProbe: SendableInheritanceProbe {
    func base(_ value: Int) -> String { "\(value)" }
    var baseValue: Int { 0 }
    func sendableChild() -> Int { 0 }
}

protocol AsyncInheritanceBaseProbe {
    func inheritedLoad(_ id: Int) async throws -> String
}

protocol AsyncInheritanceChildProbe: AsyncInheritanceBaseProbe {
    func localValue() -> Int
}

struct LinkedAsyncInheritanceProbe: AsyncInheritanceChildProbe {
    func inheritedLoad(_ id: Int) async throws -> String { "\(id)" }
    func localValue() -> Int { 0 }
}

@inline(never)
private func useLinkedAutomaticInheritance(
    _ value: any AutomaticInheritanceChildProbe
) -> String {
    value.base(0)
}

@inline(never)
private func useLinkedDiamondInheritance(_ value: any DiamondProbe) -> String {
    value.root(0)
}

@inline(never)
private func useLinkedSendableInheritance(
    _ value: any SendableInheritanceProbe
) -> Int {
    value.sendableChild()
}

@inline(never)
private func useLinkedAsyncInheritance(
    _ value: any AsyncInheritanceChildProbe
) async throws -> String {
    try await value.inheritedLoad(0)
}

@Suite struct ProtocolInheritanceTests {
    @Test func automaticDiscoverySupportsBaseMethodsGettersAndChildMethods() throws {
        #expect(useLinkedAutomaticInheritance(LinkedAutomaticInheritanceProbe()) == "0")
        let stub = try Stub<any AutomaticInheritanceChildProbe>()
        stub.when { $0.base(any()) }.then { (value: Int) in "base:\(value)" }
        stub.when { $0.baseValue }.thenReturn(42)
        stub.when { $0.child() }.thenReturn(true)

        let probe: any AutomaticInheritanceChildProbe = stub()
        #expect(probe.base(7) == "base:7")
        #expect(probe.baseValue == 42)
        #expect(probe.child())

        stub.verify { $0.base(7) }
        stub.verify { $0.baseValue }
        stub.verify { $0.child() }
    }

    @Test func explicitRequirementsAreFlatAndBaseFirst() throws {
        let stub = try Stub<any ExplicitInheritanceChildProbe>(
            .method(Int.self, returning: String.self),
            .getter(Int.self),
            .method(returning: Bool.self)
        )
        stub.when { $0.base(any()) }.then { (value: Int) in "explicit:\(value)" }
        stub.when { $0.baseValue }.thenReturn(17)
        stub.when { $0.child() }.thenReturn(true)

        let probe: any ExplicitInheritanceChildProbe = stub()
        #expect(probe.base(3) == "explicit:3")
        #expect(probe.baseValue == 17)
        #expect(probe.child())
    }

    @Test func diamondInheritanceFabricatesEachUniqueBaseOnce() throws {
        #expect(useLinkedDiamondInheritance(LinkedDiamondProbe()) == "0")
        let stub = try Stub<any DiamondProbe>()
        stub.when { $0.root(any()) }.then { (value: Int) in "root:\(value)" }
        stub.when { $0.left() }.thenReturn(2)
        stub.when { $0.right }.thenReturn("right")
        stub.when { $0.finish(any()) }.then { (value: Bool) in !value }

        let probe: any DiamondProbe = stub()
        #expect(probe.root(1) == "root:1")
        #expect(probe.left() == 2)
        #expect(probe.right == "right")
        #expect(probe.finish(false))

        stub.verify(.exactly(1)) { $0.root(1) }
        stub.verify(.exactly(1)) { $0.left() }
        stub.verify(.exactly(1)) { $0.right }
        stub.verify(.exactly(1)) { $0.finish(false) }

        // The shared root is described once, followed by the first-seen left
        // and right branches, and finally the derived protocol.
        let explicit = try Stub<any DiamondProbe>(
            .method(Int.self, returning: String.self),
            .method(returning: Int.self),
            .getter(String.self),
            .method(Bool.self, returning: Bool.self)
        )
        explicit.when { $0.root(any()) }.thenReturn("explicit-root")
        explicit.when { $0.left() }.thenReturn(3)
        explicit.when { $0.right }.thenReturn("explicit-right")
        explicit.when { $0.finish(any()) }.thenReturn(true)

        let explicitProbe: any DiamondProbe = explicit()
        #expect(explicitProbe.root(0) == "explicit-root")
        #expect(explicitProbe.left() == 3)
        #expect(explicitProbe.right == "explicit-right")
        #expect(explicitProbe.finish(false))
    }

    @Test func markerRefinementsRemainErasedBesideOrdinaryInheritance() throws {
        #expect(useLinkedSendableInheritance(LinkedSendableInheritanceProbe()) == 0)
        let stub = try Stub<any SendableInheritanceProbe>()
        stub.when { $0.base(any()) }.then { (value: Int) in "sendable:\(value)" }
        stub.when { $0.baseValue }.thenReturn(5)
        stub.when { $0.sendableChild() }.thenReturn(8)

        let probe: any SendableInheritanceProbe = stub(sendability: .unchecked)
        #expect(probe.base(4) == "sendable:4")
        #expect(probe.baseValue == 5)
        #expect(probe.sendableChild() == 8)
    }

    @Test func inheritedAsyncThrowingMethodsUseTheirBaseTableContext() async throws {
        #expect(try await useLinkedAsyncInheritance(LinkedAsyncInheritanceProbe()) == "0")
        let stub = try Stub<any AsyncInheritanceChildProbe>()
        await stub.when { try await $0.inheritedLoad(any()) }.then {
            (id: Int) async throws -> String in
            "loaded:\(id)"
        }
        stub.when { $0.localValue() }.thenReturn(9)

        let probe: any AsyncInheritanceChildProbe = stub()
        #expect(try await probe.inheritedLoad(4) == "loaded:4")
        #expect(probe.localValue() == 9)

        await stub.verify { try await $0.inheritedLoad(4) }
        stub.verify { $0.localValue() }
    }

    @Test func inheritedExplicitSignaturesAreValidatedAtGlobalIndices() {
        #expect(useLinkedAutomaticInheritance(LinkedAutomaticInheritanceProbe()) == "0")
        expectStubError({
            _ = try Stub<any AutomaticInheritanceChildProbe>(
                .method(String.self, returning: String.self),
                .getter(Int.self),
                .method(returning: Bool.self)
            )
        }) { error in
            guard case .requirementMismatch(let protocolName, let requirementIndex, _, _) = error
            else {
                return false
            }
            return protocolName == "AutomaticInheritanceBaseProbe" && requirementIndex == 0
        }
    }
}
