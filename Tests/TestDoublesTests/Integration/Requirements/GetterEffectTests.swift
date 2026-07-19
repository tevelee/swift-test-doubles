import Testing
@testable import TestDoubles

enum EffectfulGetterProbeError: Error {
    case failed
}

protocol EffectfulGetterProbe {
    var value: Int { get async throws }
}

struct RealEffectfulGetterProbe: EffectfulGetterProbe {
    var value: Int {
        get async throws { 1 }
    }
}

protocol GetterEffectMatrixProbe {
    var syncValue: Int { get }
    func betweenSyncGetters()
    var syncThrowingValue: Int { get throws }
    var asyncValue: Int { get async }
    func betweenAsyncGetters()
    var asyncThrowingValue: Int { get async throws }
}

struct RealGetterEffectMatrixProbe: GetterEffectMatrixProbe {
    var syncValue: Int { 1 }
    func betweenSyncGetters() {}
    var syncThrowingValue: Int { get throws { 2 } }
    var asyncValue: Int { get async { 3 } }
    func betweenAsyncGetters() {}
    var asyncThrowingValue: Int { get async throws { 4 } }
}

protocol ReadWriteGetterEffectProbe {
    var value: Int { get set }
}

struct RealReadWriteGetterEffectProbe: ReadWriteGetterEffectProbe {
    var value = 0
}

protocol BaseGetterEffectProbe {
    var baseValue: Int { get async }
}

protocol ChildGetterEffectProbe: BaseGetterEffectProbe {
    var childValue: String { get throws }
}

struct RealChildGetterEffectProbe: ChildGetterEffectProbe {
    var baseValue: Int { get async { 1 } }
    var childValue: String { get throws { "child" } }
}

protocol FirstRepeatedGetterEffectProbe {
    var repeated: Int { get async }
}

protocol SecondRepeatedGetterEffectProbe {
    var repeated: Int { get async throws }
}

struct RealFirstRepeatedGetterEffectProbe: FirstRepeatedGetterEffectProbe {
    var repeated: Int { get async { 1 } }
}

struct RealSecondRepeatedGetterEffectProbe: SecondRepeatedGetterEffectProbe {
    var repeated: Int { get async throws { 2 } }
}

protocol ForeignGetterEffectProbe {
    var foreignValue: Int { get }
}

struct RealForeignGetterEffectProbe: ForeignGetterEffectProbe {
    var foreignValue: Int { 0 }
}

protocol StaticGetterEffectProbe {
    static var value: Int { get async throws }
}

struct RealStaticGetterEffectProbe: StaticGetterEffectProbe {
    static var value: Int { get async throws { 1 } }
}

protocol AssociatedGetterEffectProbe<Element> {
    associatedtype Element
    var current: Element? { get async throws }
}

struct RealAssociatedGetterEffectProbe: AssociatedGetterEffectProbe {
    var current: Int? { get async throws { 1 } }
}

@Suite struct GetterEffectTests {
    @Test func asyncGetterEffectsRequireExplicitConstruction() async throws {
        _ = RealEffectfulGetterProbe()
        expectStubError({
            _ = try Stub<any EffectfulGetterProbe>()
        }) { error in
            guard case .signatureDiscoveryFailed(let protocolName, let requirementIndex, _) = error else {
                return false
            }
            return protocolName == "EffectfulGetterProbe" && requirementIndex == 0
        }

        let stub = try Stub<any EffectfulGetterProbe>(
            .getter(Int.self, isThrowing: true, isAsync: true)
        )
        await stub.when { try await $0.value }.thenReturn(7)
        #expect(try await stub().value == 7)

        expectStubError({
            _ = try Stub<any EffectfulGetterProbe>(
                .getter(String.self, isThrowing: true, isAsync: true)
            )
        }) { error in
            guard case .requirementMismatch(_, _, let expected, _) = error else {
                return false
            }
            return expected.contains("throwing effect unavailable")
        }
    }

    @Test func getterEffectHintsCoverAllFourEffectCombinations() async throws {
        _ = RealGetterEffectMatrixProbe()
        typealias ProbeStub = Stub<any GetterEffectMatrixProbe>
        let stub = try ProbeStub(
            getterEffects: .nonthrowing,
            .throwing,
            .nonthrowing,
            .throwing
        )
        stub.when { $0.syncValue }.thenReturn(10)
        stub.when { try $0.syncThrowingValue }.thenReturn(20)
        await stub.when { await $0.asyncValue }.thenReturn(30)
        await stub.when { try await $0.asyncThrowingValue }.thenReturn(40)

        let probe: any GetterEffectMatrixProbe = stub()
        #expect(probe.syncValue == 10)
        #expect(try probe.syncThrowingValue == 20)
        #expect(await probe.asyncValue == 30)
        #expect(try await probe.asyncThrowingValue == 40)

        let descriptors = try (0 ..< 6).map {
            try #require(stub.recorder.runtimeMethod(for: $0))
        }
        #expect(descriptors[0].isThrowing == false)
        #expect(descriptors[0].hasReliableThrowing)
        #expect(descriptors[1].kind == .method)
        #expect(descriptors[2].isThrowing)
        #expect(descriptors[2].hasReliableThrowing)
        #expect(descriptors[3].isThrowing == false)
        #expect(descriptors[3].isAsync)
        #expect(descriptors[3].hasReliableThrowing)
        #expect(descriptors[4].kind == .method)
        #expect(descriptors[5].isThrowing)
        #expect(descriptors[5].isAsync)
        #expect(descriptors[5].hasReliableThrowing)
    }

    @Test func throwingGetterHintsPropagateSyncAndAsyncFailures() async throws {
        _ = RealGetterEffectMatrixProbe()
        let stub = try Stub<any GetterEffectMatrixProbe>(
            getterEffects: .nonthrowing,
            .throwing,
            .nonthrowing,
            .throwing
        )
        stub.when { try $0.syncThrowingValue }.then { () throws -> Int in
            throw EffectfulGetterProbeError.failed
        }
        await stub.when { try await $0.asyncThrowingValue }.then {
            () async throws -> Int in
            throw EffectfulGetterProbeError.failed
        }

        let probe: any GetterEffectMatrixProbe = stub()
        #expect(throws: EffectfulGetterProbeError.self) {
            _ = try probe.syncThrowingValue
        }
        await #expect(throws: EffectfulGetterProbeError.self) {
            _ = try await probe.asyncThrowingValue
        }
    }

    @Test func getterHintsSkipTheSetterOfAReadWriteProperty() throws {
        _ = RealReadWriteGetterEffectProbe()
        let stub = try Stub<any ReadWriteGetterEffectProbe>(
            getterEffects: .nonthrowing
        )
        stub.when { $0.value }.thenReturn(7)
        stub.when { $0.value = any() }.thenDoNothing()

        var probe: any ReadWriteGetterEffectProbe = stub()
        #expect(probe.value == 7)
        probe.value = 9
        stub.verify { $0.value = equal(9) }

        let getter = try #require(stub.recorder.runtimeMethod(for: 0))
        let setter = try #require(stub.recorder.runtimeMethod(for: 1))
        #expect(getter.hasReliableThrowing)
        #expect(setter.kind == .setter)
        #expect(setter.isThrowing == false)
    }

    @Test func legacyDiscoveryKeepsSyncGetterEffectsUnreliable() throws {
        _ = RealReadWriteGetterEffectProbe()
        let stub = try Stub<any ReadWriteGetterEffectProbe>()
        let getter = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(getter.isThrowing == false)
        #expect(getter.hasReliableThrowing == false)
    }

    @Test func groupedGetterHintsResolveInheritanceByDeclaringProtocol() async throws {
        _ = RealChildGetterEffectProbe()
        typealias ProbeStub = Stub<any ChildGetterEffectProbe>
        let stub = try ProbeStub(
            getterEffectsByProtocol: .effects(
                declaredBy: BaseGetterEffectProbe.self,
                .nonthrowing
            ),
            .effects(
                declaredBy: ChildGetterEffectProbe.self,
                .throwing
            )
        )
        await stub.when { await $0.baseValue }.thenReturn(11)
        stub.when { try $0.childValue }.thenReturn("hinted")

        let probe: any ChildGetterEffectProbe = stub()
        #expect(await probe.baseValue == 11)
        #expect(try probe.childValue == "hinted")
    }

    @Test func groupedGetterHintsDistinguishRepeatedNamesInAComposition() async throws {
        _ = RealFirstRepeatedGetterEffectProbe()
        _ = RealSecondRepeatedGetterEffectProbe()
        typealias Probe = any FirstRepeatedGetterEffectProbe & SecondRepeatedGetterEffectProbe
        typealias ProbeStub = Stub<Probe>
        let stub = try ProbeStub(
            getterEffectsByProtocol: .effects(
                declaredBy: FirstRepeatedGetterEffectProbe.self,
                .nonthrowing
            ),
            .effects(
                declaredBy: SecondRepeatedGetterEffectProbe.self,
                .throwing
            )
        )
        await stub.when { value in
            let first: any FirstRepeatedGetterEffectProbe = value
            return await first.repeated
        }.thenReturn(11)
        await stub.when { value in
            let second: any SecondRepeatedGetterEffectProbe = value
            return try await second.repeated
        }.thenReturn(22)

        let value: Probe = stub()
        let first: any FirstRepeatedGetterEffectProbe = value
        let second: any SecondRepeatedGetterEffectProbe = value
        #expect(await first.repeated == 11)
        #expect(try await second.repeated == 22)
    }

    @Test func getterHintsSupportStaticGetters() async throws {
        _ = RealStaticGetterEffectProbe()
        let stub = try Stub<any StaticGetterEffectProbe>(
            getterEffects: .throwing
        )
        await stub.when { try await type(of: $0).value }.thenReturn(42)

        #expect(
            try await stub.withValue {
                try await type(of: $0).value
            } == 42
        )
    }

    @Test func getterHintsPreserveBoundNestedAssociatedResults() async throws {
        _ = RealAssociatedGetterEffectProbe()
        let stub = try Stub<any AssociatedGetterEffectProbe<Int>>(
            getterEffects: .throwing
        )
        await stub.when { try await $0.current }.thenReturn(42)

        #expect(try await stub().current == 42)
        let descriptor = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(descriptor.returnDependency == .associatedType(name: "Element"))
        #expect(descriptor.isThrowing)
        #expect(descriptor.hasReliableThrowing)
    }

    @Test func getterHintCountsAreExact() {
        _ = RealGetterEffectMatrixProbe()
        expectStubError({
            _ = try Stub<any GetterEffectMatrixProbe>(
                getterEffects: .nonthrowing
            )
        }) { error in
            guard case .getterEffectCountMismatch(_, let expected, let actual) = error else {
                return false
            }
            return expected == 4 && actual == 1
        }

        expectStubError({
            _ = try Stub<any GetterEffectMatrixProbe>(
                getterEffects: .nonthrowing,
                .throwing,
                .nonthrowing,
                .throwing,
                .nonthrowing
            )
        }) { error in
            guard case .getterEffectCountMismatch(_, let expected, let actual) = error else {
                return false
            }
            return expected == 4 && actual == 5
        }
    }

    @Test func groupedGetterHintsRejectMissingDuplicateAndForeignGroups() {
        _ = RealChildGetterEffectProbe()
        _ = RealForeignGetterEffectProbe()
        typealias ProbeStub = Stub<any ChildGetterEffectProbe>

        expectStubError({
            _ = try ProbeStub(
                getterEffectsByProtocol: .effects(
                    declaredBy: ChildGetterEffectProbe.self,
                    .throwing
                )
            )
        }) { error in
            guard case .missingProtocolGetterEffectGroup(let protocolName) = error else {
                return false
            }
            return protocolName == "BaseGetterEffectProbe"
        }

        expectStubError({
            _ = try ProbeStub(
                getterEffectsByProtocol: .effects(
                    declaredBy: BaseGetterEffectProbe.self,
                    .nonthrowing
                ),
                .effects(
                    declaredBy: BaseGetterEffectProbe.self,
                    .nonthrowing
                ),
                .effects(
                    declaredBy: ChildGetterEffectProbe.self,
                    .throwing
                )
            )
        }) { error in
            guard case .duplicateProtocolGetterEffectGroup(let protocolName) = error else {
                return false
            }
            return protocolName == "BaseGetterEffectProbe"
        }

        expectStubError({
            _ = try ProbeStub(
                getterEffectsByProtocol: .effects(
                    declaredBy: BaseGetterEffectProbe.self,
                    .nonthrowing
                ),
                .effects(
                    declaredBy: ChildGetterEffectProbe.self,
                    .throwing
                ),
                .effects(
                    declaredBy: ForeignGetterEffectProbe.self,
                    .nonthrowing
                )
            )
        }) { error in
            guard case .foreignProtocolGetterEffectGroup(let protocolName, _) = error else {
                return false
            }
            return protocolName == "ForeignGetterEffectProbe"
        }
    }

    @Test func groupedGetterHintCountsAreDeclarationScoped() {
        _ = RealChildGetterEffectProbe()
        expectStubError({
            _ = try Stub<any ChildGetterEffectProbe>(
                getterEffectsByProtocol: .effects(
                    declaredBy: BaseGetterEffectProbe.self,
                    .nonthrowing,
                    .nonthrowing
                ),
                .effects(
                    declaredBy: ChildGetterEffectProbe.self,
                    .throwing
                )
            )
        }) { error in
            guard
                case .getterEffectCountMismatch(
                    let protocolName,
                    let expected,
                    let actual
                ) = error
            else {
                return false
            }
            return protocolName == "BaseGetterEffectProbe" && expected == 1 && actual == 2
        }
    }

    @Test func getterHintsForACompositionMustBeGrouped() {
        _ = RealFirstRepeatedGetterEffectProbe()
        _ = RealSecondRepeatedGetterEffectProbe()
        typealias Probe = any FirstRepeatedGetterEffectProbe & SecondRepeatedGetterEffectProbe
        expectStubError({
            _ = try Stub<Probe>(
                getterEffects: .nonthrowing,
                .throwing
            )
        }) { error in
            if case .compositionRequiresGroupedGetterEffects = error {
                true
            } else {
                false
            }
        }
    }
}
