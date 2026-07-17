import Testing
@testable import TestDoubles
#if canImport(Foundation)
    import Foundation
#endif

private protocol ExplicitDynamicSelfProbe {
    func duplicate() -> Self
    func optionalDuplicate(returnValue: Bool) -> Self?
    func marker() -> Int
}

protocol DynamicSelfEffectsProbe {
    func duplicate() -> Self
    func copied(marker: Int) -> Self
    func refreshed() async throws -> Self
    func rejected() async throws -> Self
    var twin: Self { get }
    func marker() -> Int
}

struct RealDynamicSelfEffectsProbe: DynamicSelfEffectsProbe {
    func duplicate() -> Self { self }
    func copied(marker _: Int) -> Self { self }
    func refreshed() async throws -> Self { self }
    func rejected() async throws -> Self { self }
    var twin: Self { self }
    func marker() -> Int { 0 }
}

protocol ClassDynamicSelfProbe: AnyObject {
    func duplicate() -> Self
    func optionalDuplicate() -> Self?
    func marker() -> Int
}

final class RealClassDynamicSelfProbe: ClassDynamicSelfProbe {
    func duplicate() -> Self { self }
    func optionalDuplicate() -> Self? { self }
    func marker() -> Int { 0 }
}

protocol StaticDynamicSelfProbe {
    static func make() -> Self
    func marker() -> Int
}

struct RealStaticDynamicSelfProbe: StaticDynamicSelfProbe {
    static func make() -> Self { Self() }
    func marker() -> Int { 0 }
}

protocol OptionalDynamicSelfProbe {
    func duplicate(marker: Int) -> Self?
    func refreshed(returnValue: Bool) async throws -> Self?
    func rejected() throws -> Self?
    var twin: Self? { get }
    static func make() -> Self?
    func marker() -> Int
}

protocol ExistentialPeerProbe {
    func peer() -> any ExistentialPeerProbe
    static func makePeer() -> any ExistentialPeerProbe
    static func failingPeer() throws -> any ExistentialPeerProbe
}

struct RealExistentialPeerProbe: ExistentialPeerProbe {
    func peer() -> any ExistentialPeerProbe { self }
    static func makePeer() -> any ExistentialPeerProbe { Self() }
    static func failingPeer() throws -> any ExistentialPeerProbe { Self() }
}

struct RealOptionalDynamicSelfProbe: OptionalDynamicSelfProbe {
    func duplicate(marker _: Int) -> Self? { self }
    func refreshed(returnValue _: Bool) async throws -> Self? { self }
    func rejected() throws -> Self? { self }
    var twin: Self? { self }
    static func make() -> Self? { Self() }
    func marker() -> Int { 0 }
}

private protocol OptionalExistentialPeerProbe {
    func peer() -> (any OptionalExistentialPeerProbe)?
}

#if canImport(Foundation)
    private protocol SuperclassOptionalDynamicSelfProbe {
        func duplicate() -> Self?
        func marker() -> Int
    }
#endif

private enum DynamicSelfProbeError: Error {
    case rejected
}

private protocol TypedThrowingOptionalDynamicSelfProbe {
    func duplicate() throws(DynamicSelfProbeError) -> Self?
}

@Suite struct DynamicSelfResultTests {
    @Test func explicitRequirementWorksWithoutLinkedConformer() throws {
        let stub = try Stub<any ExplicitDynamicSelfProbe>(
            .method(returning: .dynamicSelf),
            .method(
                .concrete(Bool.self),
                returning: .optionalDynamicSelf
            ),
            .method(returning: Int.self)
        )
        stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
        stub.when(
            returningOptionalSelf: {
                $0.optionalDuplicate(returnValue: any())
            }
        ).then { (returnValue: Bool) -> StubOptionalSelfResultBuilder.Outcome in
            returnValue ? .returnValue : .returnNil
        }
        stub.when { $0.marker() }.thenReturn(42)

        let duplicate = stub().duplicate()
        let optionalDuplicate = stub().optionalDuplicate(returnValue: true)

        #expect(duplicate.marker() == 42)
        #expect(optionalDuplicate?.marker() == 42)
        #expect(stub().optionalDuplicate(returnValue: false) == nil)
        stub.verify(.exactly(1)) { $0.duplicate() }
        stub.verify(.exactly(2)) {
            $0.optionalDuplicate(returnValue: any())
        }
    }

    @Test func automaticMethodsAndGetterReturnValuesFromTheSameRuntimeGraph() throws {
        _ = RealDynamicSelfEffectsProbe()
        let stub = try Stub<any DynamicSelfEffectsProbe>()
        stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
        stub.when(returningSelf: { $0.copied(marker: equal(5)) }).then {
            (marker: Int) throws -> Void in
            #expect(marker == 5)
        }
        stub.when(returningSelf: { $0.twin }).thenReturnValue()
        stub.when { $0.marker() }.thenReturn(7)

        let source = stub()
        let duplicate = source.duplicate()
        let copy = source.copied(marker: 5)
        let twin = source.twin

        #expect(duplicate.marker() == 7)
        #expect(copy.marker() == 7)
        #expect(twin.marker() == 7)
        stub.verify(.exactly(1)) { $0.duplicate() }
        stub.verify(.exactly(1)) { $0.twin }
    }

    @Test func staticMethodReturnsAValueFromTheSameRuntimeGraph() throws {
        _ = RealStaticDynamicSelfProbe()
        let stub = try Stub<any StaticDynamicSelfProbe>()
        stub.when(returningSelf: { type(of: $0).make() }).thenReturnValue()
        stub.when { $0.marker() }.thenReturn(17)

        let made = stub.withValue { type(of: $0).make() }

        #expect(made.marker() == 17)
        stub.verify(.exactly(1)) { type(of: $0).make() }
    }

    @Test func asyncThrowingHandlersPreserveSuccessAndFailure() async throws {
        _ = RealDynamicSelfEffectsProbe()
        let stub = try Stub<any DynamicSelfEffectsProbe>()
        await stub.when(returningSelf: { try await $0.refreshed() }).then {
            () async throws -> Void in
        }
        await stub.when(returningSelf: { try await $0.rejected() })
            .thenThrow(DynamicSelfProbeError.rejected)
        stub.when { $0.marker() }.thenReturn(9)

        let source = stub()
        let refreshed = try await source.refreshed()

        #expect(refreshed.marker() == 9)
        await #expect(throws: DynamicSelfProbeError.self) {
            _ = try await source.rejected()
        }
    }

    @Test func returnedValueOutlivesTheOriginalStubAndSource() throws {
        func makeReturnedValue() throws -> any DynamicSelfEffectsProbe {
            _ = RealDynamicSelfEffectsProbe()
            let stub = try Stub<any DynamicSelfEffectsProbe>()
            stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
            stub.when { $0.marker() }.thenReturn(23)
            let source = stub()
            return source.duplicate()
        }

        let returned = try makeReturnedValue()

        #expect(returned.marker() == 23)
    }

    @Test func classConstrainedResultsAreFreshAndShareTheRecorder() throws {
        _ = RealClassDynamicSelfProbe()
        let stub = try Stub<any ClassDynamicSelfProbe>()
        stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
        stub.when { $0.marker() }.thenReturn(31)

        let source = stub()
        let first = source.duplicate()
        let second = source.duplicate()

        #expect(first !== second)
        #expect(first.marker() == 31)
        #expect(second.marker() == 31)
    }

    @Test func optionalSelfMethodsGettersAndStaticRequirementsReturnValueOrNil() throws {
        _ = RealOptionalDynamicSelfProbe()
        let stub = try Stub<any OptionalDynamicSelfProbe>()
        stub.when(
            returningOptionalSelf: { $0.duplicate(marker: equal(1)) }
        ).thenReturnValue()
        stub.when(
            returningOptionalSelf: { $0.duplicate(marker: equal(2)) }
        ).thenReturnNil()
        stub.when(returningOptionalSelf: { $0.twin }).thenReturnValue()
        stub.when(
            returningOptionalSelf: { type(of: $0).make() }
        ).thenReturnNil()
        stub.when { $0.marker() }.thenReturn(47)

        let source = stub()
        let duplicate = source.duplicate(marker: 1)
        let missing = source.duplicate(marker: 2)
        let twin = source.twin
        let made = stub.withValue { type(of: $0).make() }

        #expect(duplicate?.marker() == 47)
        #expect(missing == nil)
        #expect(twin?.marker() == 47)
        #expect(made == nil)
        stub.verify(.exactly(1)) { $0.duplicate(marker: equal(1)) }
        stub.verify(.exactly(1)) { $0.duplicate(marker: equal(2)) }
        stub.verify(.exactly(1)) { $0.twin }
        stub.verify(.exactly(1)) { type(of: $0).make() }
    }

    @Test func optionalSelfAsyncHandlersAndUntypedThrowsPreserveOutcomes() async throws {
        _ = RealOptionalDynamicSelfProbe()
        let stub = try Stub<any OptionalDynamicSelfProbe>()
        await stub.when(
            returningOptionalSelf: {
                try await $0.refreshed(returnValue: any())
            }
        ).then {
            (returnValue: Bool) async throws -> StubOptionalSelfResultBuilder.Outcome in
            returnValue ? .returnValue : .returnNil
        }
        stub.when(returningOptionalSelf: { try $0.rejected() })
            .thenThrow(DynamicSelfProbeError.rejected)
        stub.when { $0.marker() }.thenReturn(53)

        let source = stub()
        let refreshed = try await source.refreshed(returnValue: true)

        #expect(refreshed?.marker() == 53)
        #expect(try await source.refreshed(returnValue: false) == nil)
        #expect(throws: DynamicSelfProbeError.self) {
            _ = try source.rejected()
        }
    }

    @Test func classConstrainedOptionalSelfReturnsFreshValues() throws {
        _ = RealClassDynamicSelfProbe()
        let stub = try Stub<any ClassDynamicSelfProbe>()
        stub.when(
            returningOptionalSelf: { $0.optionalDuplicate() }
        ).thenReturnValue()
        stub.when { $0.marker() }.thenReturn(59)

        let source = stub()
        let first = try #require(source.optionalDuplicate())
        let second = try #require(source.optionalDuplicate())

        #expect(first !== second)
        #expect(first.marker() == 59)
        #expect(second.marker() == 59)
    }

    @Test func optionalSelfReturnedValueOutlivesTheOriginalStubAndSource() throws {
        func makeReturnedValue() throws -> (any OptionalDynamicSelfProbe)? {
            _ = RealOptionalDynamicSelfProbe()
            let stub = try Stub<any OptionalDynamicSelfProbe>()
            stub.when(
                returningOptionalSelf: { $0.duplicate(marker: equal(1)) }
            ).thenReturnValue()
            stub.when { $0.marker() }.thenReturn(61)
            return stub().duplicate(marker: 1)
        }

        let optionalReturned = try makeReturnedValue()
        let returned = try #require(optionalReturned)

        #expect(returned.marker() == 61)
    }

    #if canImport(Foundation)
        @Test func superclassConstrainedOptionalSelfFailsClosed() {
            #if canImport(ObjectiveC)
                let expectedReason = "separate subclass metadata"
            #else
                let expectedReason = "Objective-C runtime"
            #endif
            expectUnsupportedProtocolShape(containing: expectedReason) {
                _ = try Stub<any NSObject & SuperclassOptionalDynamicSelfProbe>(
                    .method(returning: .optionalDynamicSelf),
                    .method(returning: Int.self)
                )
            }
        }
    #endif

    @Test func typedThrowingOptionalSelfRemainsUnsupported() {
        expectUnsupportedProtocolShape(containing: "typed throws") {
            _ = try Stub<any TypedThrowingOptionalDynamicSelfProbe>(
                .method(
                    returning: .optionalDynamicSelf,
                    throwing: DynamicSelfProbeError.self
                )
            )
        }
    }

    @Test func missingOptionalSelfStubDiagnosticSuggestsTheDedicatedBuilder() {
        let method = MethodDescriptor(
            kind: .method,
            origin: .automatic,
            name: "duplicate()",
            index: 0,
            argumentTypes: [],
            returnType: Optional<StubPayload>.self,
            returnConvention: .optionalSelf,
            isThrowing: false,
            isAsync: false
        )
        let message = StubRecorder(methods: [method]).diagnosticMessage(
            title: "No stub configured",
            method: method,
            args: [],
            entries: []
        )

        #expect(
            message.contains(
                "stub.when(returningOptionalSelf: { $0.duplicate() }).thenReturnValue()"
            )
        )
    }

    @Test func ordinaryOptionalSameProtocolExistentialResultsStillSelectStubBuilder() {
        _ = configureOrdinaryOptionalPeer
    }

    @Test func ordinarySameProtocolExistentialResultsStillSelectStubBuilder() {
        _ = configureOrdinaryPeer
    }

    @Test func ordinaryStaticExistentialResultsStillSelectStubBuilder() throws {
        let stub = try Stub<any ExistentialPeerProbe>(
            .method(returning: (any ExistentialPeerProbe).self),
            .method(returning: (any ExistentialPeerProbe).self),
            .method(returning: (any ExistentialPeerProbe).self, isThrowing: true)
        )
        let peer: any ExistentialPeerProbe = RealExistentialPeerProbe()
        stub.when(returning: peer) { type(of: $0).makePeer() }.thenReturn(peer)
        stub.when(returning: peer) { try type(of: $0).failingPeer() }
            .thenThrow(DynamicSelfProbeError.rejected)

        let value: any ExistentialPeerProbe = stub()
        #expect(type(of: value).makePeer() is RealExistentialPeerProbe)
        #expect(throws: DynamicSelfProbeError.self) {
            _ = try type(of: value).failingPeer()
        }
        stub.verify(returning: peer) { type(of: $0).makePeer() }
        stub.verify(returning: peer) { try type(of: $0).failingPeer() }
    }

    @Test func directSelfArgumentsRemainUnsupportedWithAnActionableError() {
        expectUnsupportedProtocolShape(containing: "direct Self argument") {
            _ = try Stub<any SelfArgumentRequirementProbe>()
        }
    }
}

private func configureOrdinaryPeer(
    _ stub: Stub<any ExistentialPeerProbe>,
    returning peer: any ExistentialPeerProbe
) {
    stub.when { $0.peer() }.thenReturn(peer)
}

private func configureOrdinaryOptionalPeer(
    _ stub: Stub<any OptionalExistentialPeerProbe>,
    returning peer: (any OptionalExistentialPeerProbe)?
) {
    stub.when(returning: peer) { $0.peer() }.thenReturn(peer)
}
