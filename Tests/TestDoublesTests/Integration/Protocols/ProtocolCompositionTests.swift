import Testing
@testable import TestDoubles

protocol AutomaticCompositionA {
    func transform(_ value: Int) -> String
    var count: Int { get }
}

protocol AutomaticCompositionB {
    func isEnabled(_ key: String) async throws -> Bool
}

struct LinkedAutomaticCompositionA: AutomaticCompositionA {
    func transform(_ value: Int) -> String { "\(value)" }
    var count: Int { 0 }
}

struct LinkedAutomaticCompositionB: AutomaticCompositionB {
    func isEnabled(_ key: String) async throws -> Bool { false }
}

private protocol ExplicitCompositionA {
    func transform(_ value: Int) -> String
}

private protocol ExplicitCompositionB {
    var enabled: Bool { get }
}

private protocol ForeignCompositionProtocol {
    func foreign()
}

protocol SharedCompositionBase {
    func shared(_ value: Int) -> String
}

protocol SharedCompositionLeft: SharedCompositionBase {
    func left() -> Int
}

protocol SharedCompositionRight: SharedCompositionBase {
    var right: String { get }
}

struct LinkedSharedCompositionLeft: SharedCompositionLeft {
    func shared(_ value: Int) -> String { "\(value)" }
    func left() -> Int { 0 }
}

struct LinkedSharedCompositionRight: SharedCompositionRight {
    func shared(_ value: Int) -> String { "\(value)" }
    var right: String { "" }
}

protocol MarkerCompositionProtocol {
    func markerValue() -> Int
}

struct LinkedMarkerCompositionProtocol: MarkerCompositionProtocol, Sendable {
    func markerValue() -> Int { 0 }
}

private protocol EmptyCompositionA {}
private protocol EmptyCompositionB {}

@inline(never)
func useLinkedAutomaticCompositionA(
    _ value: any AutomaticCompositionA
) -> String {
    value.transform(0)
}

@inline(never)
func useLinkedAutomaticCompositionB(
    _ value: any AutomaticCompositionB
) async throws -> Bool {
    try await value.isEnabled("link")
}

@inline(never)
func useLinkedSharedCompositionLeft(
    _ value: any SharedCompositionLeft
) -> Int {
    value.left()
}

@inline(never)
func useLinkedSharedCompositionRight(
    _ value: any SharedCompositionRight
) -> String {
    value.right
}

@inline(never)
func useLinkedMarkerComposition(
    _ value: any MarkerCompositionProtocol & Sendable
) -> Int {
    value.markerValue()
}

@Suite struct ProtocolCompositionTests {
    @Test func automaticDiscoveryUsesIndependentRootConformances() async throws {
        #expect(useLinkedAutomaticCompositionA(LinkedAutomaticCompositionA()) == "0")
        #expect(try await useLinkedAutomaticCompositionB(LinkedAutomaticCompositionB()) == false)
        let stub = try Stub<any AutomaticCompositionA & AutomaticCompositionB>()
        stub.when { $0.transform(any()) }.then { (value: Int) in "value:\(value)" }
        stub.when { $0.count }.thenReturn(3)
        await stub.when { try await $0.isEnabled(any()) }.then {
            (key: String) async throws -> Bool in
            key == "feature"
        }

        let probe: any AutomaticCompositionA & AutomaticCompositionB = stub()
        #expect(probe.transform(2) == "value:2")
        #expect(probe.count == 3)
        #expect(try await probe.isEnabled("feature"))

        stub.verify { $0.transform(2) }
        stub.verify { $0.count }
        await stub.verify { try await $0.isEnabled("feature") }
    }

    @Test func groupedExplicitRequirementsAreOrderIndependentAndUseBareProtocolTypes() throws {
        let stub = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
            requirementsByProtocol: .requirements(
                declaredBy: ExplicitCompositionB.self,
                .getter(Bool.self)
            ),
            .requirements(
                declaredBy: ExplicitCompositionA.self,
                .method(Int.self, returning: String.self)
            )
        )
        stub.when { $0.transform(any()) }.then { (value: Int) in "explicit:\(value)" }
        stub.when { $0.enabled }.thenReturn(true)

        let probe: any ExplicitCompositionA & ExplicitCompositionB = stub()
        #expect(probe.transform(4) == "explicit:4")
        #expect(probe.enabled)
    }

    @Test func linkedRootsStillValidateWhenAnotherCompositionRootIsUnlinked() {
        #expect(useLinkedAutomaticCompositionA(LinkedAutomaticCompositionA()) == "0")
        expectStubError({
            _ = try Stub<any AutomaticCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: AutomaticCompositionA.self,
                    .method(String.self, returning: String.self),
                    .getter(Int.self)
                ),
                .requirements(
                    declaredBy: ExplicitCompositionB.self,
                    .getter(Bool.self)
                )
            )
        }) { error in
            guard case .requirementMismatch(let protocolName, _, _, _) = error else {
                return false
            }
            return protocolName == "AutomaticCompositionA"
        }
    }

    @Test func sharedInheritedProtocolsAreDescribedAndFabricatedOnce() throws {
        #expect(useLinkedSharedCompositionLeft(LinkedSharedCompositionLeft()) == 0)
        #expect(useLinkedSharedCompositionRight(LinkedSharedCompositionRight()) == "")
        let automatic = try Stub<any SharedCompositionLeft & SharedCompositionRight>()
        automatic.when { $0.shared(any()) }.then { (value: Int) in "shared:\(value)" }
        automatic.when { $0.left() }.thenReturn(1)
        automatic.when { $0.right }.thenReturn("right")

        let automaticProbe: any SharedCompositionLeft & SharedCompositionRight = automatic()
        #expect(automaticProbe.shared(7) == "shared:7")
        #expect(automaticProbe.left() == 1)
        #expect(automaticProbe.right == "right")

        let explicit = try Stub<any SharedCompositionLeft & SharedCompositionRight>(
            requirementsByProtocol: .requirements(
                declaredBy: SharedCompositionRight.self,
                .getter(String.self)
            ),
            .requirements(
                declaredBy: SharedCompositionBase.self,
                .method(Int.self, returning: String.self)
            ),
            .requirements(
                declaredBy: SharedCompositionLeft.self,
                .method(returning: Int.self)
            )
        )
        explicit.when { $0.shared(any()) }.thenReturn("explicit-shared")
        explicit.when { $0.left() }.thenReturn(2)
        explicit.when { $0.right }.thenReturn("explicit-right")

        let explicitProbe: any SharedCompositionLeft & SharedCompositionRight = explicit()
        #expect(explicitProbe.shared(0) == "explicit-shared")
        #expect(explicitProbe.left() == 2)
        #expect(explicitProbe.right == "explicit-right")
    }

    @Test func markerCompositionDoesNotAddWitnessStorage() throws {
        #expect(useLinkedMarkerComposition(LinkedMarkerCompositionProtocol()) == 0)
        let stub = try Stub<any MarkerCompositionProtocol & Sendable>()
        stub.when { $0.markerValue() }.thenReturn(42)

        let probe: any MarkerCompositionProtocol & Sendable = stub()
        #expect(probe.markerValue() == 42)
    }

    @Test func emptyProtocolCompositionAcceptsAnEmptyGroupedArray() throws {
        let stub = try Stub<any EmptyCompositionA & EmptyCompositionB>(
            requirementsByProtocol: []
        )
        let _: any EmptyCompositionA & EmptyCompositionB = stub()
    }

    @Test func flatExplicitRequirementsRejectMultiRootCompositions() {
        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                .method(Int.self, returning: String.self),
                .getter(Bool.self)
            )
        }) { error in
            guard case .compositionRequiresGroupedRequirements = error else { return false }
            return true
        }
    }

    @Test func missingDuplicateForeignAndInvalidGroupsAreDiagnosed() {
        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: ExplicitCompositionA.self,
                    .method(Int.self, returning: String.self)
                )
            )
        }) { error in
            guard case .missingProtocolRequirementGroup(let protocolName) = error else {
                return false
            }
            return protocolName == "ExplicitCompositionB"
        }

        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: ExplicitCompositionA.self,
                    .method(Int.self, returning: String.self)
                ),
                .requirements(
                    declaredBy: ExplicitCompositionA.self,
                    .method(Int.self, returning: String.self)
                )
            )
        }) { error in
            guard case .duplicateProtocolRequirementGroup(let protocolName) = error else {
                return false
            }
            return protocolName == "ExplicitCompositionA"
        }

        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: ForeignCompositionProtocol.self,
                    .method(returning: Void.self)
                )
            )
        }) { error in
            guard case .foreignProtocolRequirementGroup(let protocolName, _) = error else {
                return false
            }
            return protocolName == "ForeignCompositionProtocol"
        }

        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: Int.self,
                    .method(returning: Void.self)
                )
            )
        }) { error in
            guard case .invalidProtocolRequirementGroup(let typeDescription) = error else {
                return false
            }
            return typeDescription == "Swift.Int"
        }
    }

    @Test func groupedRequirementCountsAndKindsAreValidatedPerProtocol() {
        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: ExplicitCompositionA.self
                ),
                .requirements(
                    declaredBy: ExplicitCompositionB.self,
                    .getter(Bool.self)
                )
            )
        }) { error in
            guard
                case .requirementCountMismatch(
                    let protocolName,
                    let expected,
                    let actual
                ) = error
            else {
                return false
            }
            return protocolName == "ExplicitCompositionA" && expected == 1 && actual == 0
        }

        expectStubError({
            _ = try Stub<any ExplicitCompositionA & ExplicitCompositionB>(
                requirementsByProtocol: .requirements(
                    declaredBy: ExplicitCompositionA.self,
                    .getter(String.self)
                ),
                .requirements(
                    declaredBy: ExplicitCompositionB.self,
                    .getter(Bool.self)
                )
            )
        }) { error in
            guard
                case .requirementMismatch(
                    let protocolName,
                    _,
                    let expected,
                    let actual
                ) = error
            else {
                return false
            }
            return protocolName == "ExplicitCompositionA" && expected == "method" && actual == "getter"
        }
    }
}
