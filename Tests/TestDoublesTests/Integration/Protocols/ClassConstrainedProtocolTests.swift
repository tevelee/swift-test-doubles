import Foundation
import Testing
@testable import TestDoubles

protocol AutomaticClassProbe: AnyObject {
    func transform(_ value: Int) -> String
    var label: String { get }
}

final class LinkedAutomaticClassProbe: AutomaticClassProbe {
    func transform(_ value: Int) -> String { "linked-\(value)" }
    var label: String { "linked" }
}

private protocol ExplicitClassProbe: AnyObject {
    func transform(_ value: Int) -> Int
}

protocol ClassInheritanceBaseProbe: AnyObject {
    func baseValue() -> Int
}

protocol ClassInheritanceChildProbe: ClassInheritanceBaseProbe {
    func childValue() -> String
}

final class LinkedClassInheritanceProbe: ClassInheritanceChildProbe {
    func baseValue() -> Int { 0 }
    func childValue() -> String { "" }
}

private protocol ClassLifetimeProbe: AnyObject {
    func value() -> Int
}

private protocol ConcurrentClassProbe: AnyObject, Sendable {
    func doubled(_ value: Int) -> Int
}

class RequiredSuperclass: NSObject {
    let inheritedValue = 17

    func inheritedDescription() -> String {
        "required-superclass"
    }
}

protocol SuperclassConstraintProbe {
    func value() -> Int
}

final class LinkedSuperclassConstraintProbe:
    RequiredSuperclass, SuperclassConstraintProbe
{
    func value() -> Int { 0 }
}

protocol SecondSuperclassConstraintProbe {
    func text() -> String
}

final class LinkedSuperclassCompositionProbe:
    RequiredSuperclass, SuperclassConstraintProbe, SecondSuperclassConstraintProbe
{
    func value() -> Int { 0 }
    func text() -> String { "" }
}

private protocol SuperclassDynamicSelfProbe {
    func duplicate() -> Self
    func marker() -> Int
}

protocol SuperclassStaticProbe {
    static func defaultValue() -> Int
    func value() -> Int
}

private protocol SuperclassInitializerProbe {
    init(value: Int)
}

final class LinkedSuperclassStaticProbe:
    RequiredSuperclass, SuperclassStaticProbe
{
    static func defaultValue() -> Int { 0 }
    func value() -> Int { 0 }
}

private class NativeRequiredSuperclass {}

private protocol NativeSuperclassConstraintProbe {
    func value() -> Int
}

#if canImport(ObjectiveC)
    private protocol ImportedSuperclassConstraintProbe {
        func value() -> Int
    }
#endif

#if canImport(ObjectiveC)
    @objc private protocol ObjectiveCClassProbe: AnyObject {
        func call()
    }
#endif

private final class WeakClassLifetimeProbe {
    weak var value: (any ClassLifetimeProbe)?

    init(_ value: (any ClassLifetimeProbe)?) {
        self.value = value
    }
}

@inline(never)
private func exerciseLinkedAutomaticClassProbe(
    _ probe: any AutomaticClassProbe
) -> String {
    probe.transform(1) + probe.label
}

@inline(never)
private func exerciseLinkedClassInheritanceProbe(
    _ probe: any ClassInheritanceChildProbe
) -> String {
    "\(probe.baseValue()):\(probe.childValue())"
}

@inline(never)
private func exerciseLinkedSuperclassConstraintProbe(
    _ probe: any RequiredSuperclass & SuperclassConstraintProbe
) -> Int {
    probe.inheritedValue + probe.value()
}

@inline(never)
private func exerciseLinkedSuperclassCompositionProbe(
    _ probe: any RequiredSuperclass & SuperclassConstraintProbe
        & SecondSuperclassConstraintProbe
) -> String {
    "\(probe.value()):\(probe.text())"
}

@inline(never)
private func exerciseLinkedSuperclassStaticProbe(
    _ probe: any RequiredSuperclass & SuperclassStaticProbe
) -> Int {
    type(of: probe).defaultValue()
}

private func exerciseClassPayloadLifetime() throws -> (
    weakPayload: WeakClassLifetimeProbe,
    reusedPayload: Bool,
    survivedStub: Bool,
    value: Int
) {
    var stub: Stub<any ClassLifetimeProbe>? = try Stub(
        .method(returning: Int.self)
    )
    stub?.when { $0.value() }.thenReturn(42)
    let probe = try #require(stub?())
    let secondProbe = try #require(stub?())
    let weakPayload = WeakClassLifetimeProbe(probe)
    let reusedPayload = probe === secondProbe

    stub = nil

    return (
        weakPayload,
        reusedPayload,
        weakPayload.value != nil,
        probe.value()
    )
}

private func exerciseSuperclassPayloadLifetime() throws -> (
    weakPayload: WeakReference<RequiredSuperclass>,
    reusedPayload: Bool,
    survivedStub: Bool,
    value: Int
) {
    var stub: Stub<any RequiredSuperclass & SuperclassConstraintProbe>? = try Stub()
    stub?.when { $0.value() }.thenReturn(42)
    let probe = try #require(stub?())
    let secondProbe = try #require(stub?())
    let weakPayload = WeakReference<RequiredSuperclass>(probe)
    let reusedPayload = probe === secondProbe

    stub = nil

    return (
        weakPayload,
        reusedPayload,
        weakPayload.value != nil,
        probe.value()
    )
}

@Suite struct ClassConstrainedProtocolTests {
    @Test func automaticConstructionSupportsClassExistentials() throws {
        #expect(
            exerciseLinkedAutomaticClassProbe(LinkedAutomaticClassProbe()) == "linked-1linked"
        )
        let stub = try Stub<any AutomaticClassProbe>()
        stub.when { $0.transform(any()) }.then { (value: Int) in
            "stub-\(value)"
        }
        stub.when { $0.label }.thenReturn("class")

        let probe: any AutomaticClassProbe = stub()

        #expect(probe.transform(42) == "stub-42")
        #expect(probe.label == "class")
        stub.verify { $0.transform(equal(42)) }
        stub.verify { $0.label }
    }

    @Test func explicitConstructionSupportsClassExistentials() throws {
        let stub = try Stub<any ExplicitClassProbe>(
            .method(Int.self, returning: Int.self)
        )
        stub.when { $0.transform(any()) }.then { (value: Int) in
            value * 3
        }

        let probe: any ExplicitClassProbe = stub()

        #expect(probe.transform(14) == 42)
        stub.verify { $0.transform(equal(14)) }
    }

    @Test func inheritedClassProtocolsUseTheirDeclaringWitnessTables() throws {
        #expect(
            exerciseLinkedClassInheritanceProbe(LinkedClassInheritanceProbe()) == "0:"
        )
        let stub = try Stub<any ClassInheritanceChildProbe>()
        stub.when { $0.baseValue() }.thenReturn(21)
        stub.when { $0.childValue() }.thenReturn("child")

        let probe: any ClassInheritanceChildProbe = stub()

        #expect(probe.baseValue() == 21)
        #expect(probe.childValue() == "child")
    }

    @Test func classExistentialOutlivesItsStub() throws {
        var stub: Stub<any ClassLifetimeProbe>? = try Stub(
            .method(returning: Int.self)
        )
        stub?.when { $0.value() }.thenReturn(42)
        let probe = try #require(stub?())
        let weakStub = WeakReference(stub)

        stub = nil

        #expect(weakStub.value == nil)
        #expect(probe.value() == 42)
    }

    @Test func classExistentialOwnsThePayloadForExactlyItsLifetime() throws {
        let result = try exerciseClassPayloadLifetime()

        #expect(result.reusedPayload)
        #expect(result.survivedStub)
        #expect(result.value == 42)
        #expect(result.weakPayload.value == nil)
    }

    @Test func sendableClassExistentialSupportsConcurrentCalls() async throws {
        let stub = try Stub<any ConcurrentClassProbe>(
            .method(Int.self, returning: Int.self)
        )
        stub.when { $0.doubled(any()) }.then { (value: Int) in
            value * 2
        }
        let probe: any ConcurrentClassProbe = stub()

        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for value in 0 ..< 50 {
                group.addTask {
                    probe.doubled(value)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results.sorted() == (0 ..< 50).map { $0 * 2 })
        stub.verify(.exactly(50)) { $0.doubled(any()) }
    }

    #if canImport(ObjectiveC)
        @Test func automaticConstructionSupportsNSObjectBackedSuperclassConstraints() throws {
            #expect(
                exerciseLinkedSuperclassConstraintProbe(
                    LinkedSuperclassConstraintProbe()
                ) == 17
            )
            let stub = try Stub<any RequiredSuperclass & SuperclassConstraintProbe>()
            stub.when { $0.value() }.thenReturn(25)

            let probe: any RequiredSuperclass & SuperclassConstraintProbe = stub()

            #expect(probe.value() == 25)
            #expect(probe.inheritedValue == 17)
            #expect(probe.inheritedDescription() == "required-superclass")
            #expect(type(of: probe) == RequiredSuperclass.self)
            stub.verify { $0.value() }
        }

        @Test func superclassExistentialOwnsItsRuntimeResources() throws {
            let result = try exerciseSuperclassPayloadLifetime()

            #expect(result.reusedPayload)
            #expect(result.survivedStub)
            #expect(result.value == 42)
            #expect(result.weakPayload.value == nil)
        }

        @Test func superclassConstraintsComposeMultipleSwiftProtocols() throws {
            #expect(
                exerciseLinkedSuperclassCompositionProbe(
                    LinkedSuperclassCompositionProbe()
                ) == "0:"
            )
            let stub = try Stub<
                any RequiredSuperclass & SuperclassConstraintProbe
                    & SecondSuperclassConstraintProbe
            >()
            stub.when { $0.value() }.thenReturn(7)
            stub.when { $0.text() }.thenReturn("composed")

            let probe = stub()

            #expect(probe.value() == 7)
            #expect(probe.text() == "composed")
            #expect(probe.inheritedValue == 17)
        }

        @Test func superclassConstraintsSupportStaticProtocolRequirements() throws {
            #expect(
                exerciseLinkedSuperclassStaticProbe(
                    LinkedSuperclassStaticProbe()
                ) == 0
            )
            let stub = try Stub<any RequiredSuperclass & SuperclassStaticProbe>()
            stub.when { type(of: $0).defaultValue() }.thenReturn(99)
            stub.when { $0.value() }.thenReturn(1)

            let defaultValue = stub.withValue { type(of: $0).defaultValue() }

            #expect(defaultValue == 99)
            #expect(stub().value() == 1)
        }

        @Test func superclassConstrainedDynamicSelfFailsClosed() {
            expectUnsupportedProtocolShape(containing: "separate subclass metadata") {
                _ = try Stub<any RequiredSuperclass & SuperclassDynamicSelfProbe>(
                    .method(returning: .dynamicSelf),
                    .method(returning: Int.self)
                )
            }
        }

        @Test func superclassConstrainedInitializersFailClosed() {
            expectUnsupportedProtocolShape(containing: "separate subclass metadata") {
                _ = try Stub<any RequiredSuperclass & SuperclassInitializerProbe>(
                    .initializer(Int.self)
                )
            }
        }

        @Test func explicitConstructionSupportsImportedObjectiveCSuperclasses() throws {
            let stub = try Stub<any NSObject & ImportedSuperclassConstraintProbe>(
                .method(returning: Int.self)
            )
            stub.when { $0.value() }.thenReturn(42)

            let probe: any NSObject & ImportedSuperclassConstraintProbe = stub()

            #expect(probe.value() == 42)
            #expect(probe.isEqual(probe))
            #expect(type(of: probe) == NSObject.self)
        }
    #endif

    @Test func nativeSuperclassAndSpecialProtocolBoundariesFailClosed() {
        expectUnsupportedProtocolShape(containing: "NSObject-backed") {
            _ = try Stub<any NativeRequiredSuperclass & NativeSuperclassConstraintProbe>(
                .method(returning: Int.self)
            )
        }
        expectUnsupportedProtocolShape {
            _ = try Stub<any Error>()
        }
    }

    #if canImport(ObjectiveC)
        @Test func objectiveCOnlyProtocolFailsClosed() {
            // Objective-C existentials do not expose an ordinary Swift witness
            // table, so either metadata extraction or shape validation rejects
            // them before allocation.
            expectStubError({
                _ = try Stub<any ObjectiveCClassProbe>(
                    .method(returning: Void.self)
                )
            }) { _ in true }
        }
    #endif
}
