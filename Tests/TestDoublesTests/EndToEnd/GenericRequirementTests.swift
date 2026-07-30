import Testing
import TestDoubles
import TestDoublesFixtures

/// End-to-end coverage for requirement-level generic parameters (`func
/// f<T>(...)`) using an event bus, a generic equality check, and a
/// type-erased cache.
@Suite struct GenericRequirementTests {
    private struct UserRegistered: Equatable {
        let userID: Int
    }

    private struct OrderShipped: Equatable {
        let orderID: String
    }

    @Test func automaticStubRecordsAPublishedEvent() throws {
        let captor = Match.Capture<UserRegistered>()
        let stub = try Stub<any EventBus>()
        stub.when { $0.publish(captor.capture()) }.thenReturn(())

        let bus: any EventBus = stub()
        bus.publish(UserRegistered(userID: 42))

        #expect(captor.first == UserRegistered(userID: 42))
        stub.verify(.exactly(1)) {
            $0.publish(Match.any(using: UserRegistered(userID: 0)))
        }
    }

    /// `Match.equal(_:)` discriminates by type via its internal cast; `Match.any()` does not.
    @Test func automaticStubDistinguishesDifferentEventTypesAtTheSameRequirement() throws {
        let stub = try Stub<any EventBus>()
        stub.when { $0.publish(Match.equal(UserRegistered(userID: 1))) }.thenReturn(())
        stub.when { $0.publish(Match.equal(UserRegistered(userID: 2))) }.thenReturn(())
        stub.when { $0.publish(Match.equal(OrderShipped(orderID: "A-1"))) }.thenReturn(())

        let bus: any EventBus = stub()
        bus.publish(UserRegistered(userID: 1))
        bus.publish(OrderShipped(orderID: "A-1"))
        bus.publish(UserRegistered(userID: 2))

        stub.verify(.exactly(1)) { $0.publish(Match.equal(UserRegistered(userID: 1))) }
        stub.verify(.exactly(1)) { $0.publish(Match.equal(UserRegistered(userID: 2))) }
        stub.verify(.exactly(1)) { $0.publish(Match.equal(OrderShipped(orderID: "A-1"))) }
    }

    @Test func automaticStubHandlesTwoArgumentsSharingOneGenericParameter() throws {
        let stub = try Stub<any EqualityChecker>()
        stub.when { $0.areEqual(Match.equal(1), Match.equal(1)) }.thenReturn(true)
        stub.when { $0.areEqual(Match.equal("a"), Match.equal("b")) }.thenReturn(false)

        let checker: any EqualityChecker = stub()

        #expect(checker.areEqual(1, 1) == true)
        #expect(checker.areEqual("a", "b") == false)
    }

    @Test func automaticStubHandlesTwoDistinctGenericParameters() throws {
        let stub = try Stub<any GenericCache>()
        stub.when { $0.store(Match.equal("value"), forKey: Match.equal(7)) }.thenReturn(())

        let cache: any GenericCache = stub()
        cache.store("value", forKey: 7)

        stub.verify(.exactly(1)) {
            $0.store(Match.any(using: ""), forKey: Match.equal(7))
        }
    }

    @Test func explicitRequirementDescribesAGenericParameterArgument() throws {
        let stub = try Stub<any EventBus>(
            .method(.methodGenericParameter(), returning: .concrete(Void.self))
        )
        stub.when { $0.publish(Match.any(using: UserRegistered(userID: 0))) }.thenReturn(())

        let bus: any EventBus = stub()
        bus.publish(UserRegistered(userID: 9))

        stub.verify(.exactly(1)) {
            $0.publish(Match.any(using: UserRegistered(userID: 0)))
        }
    }

    @Test func explicitRequirementAcceptsDenseGenericParameterIndices() throws {
        let stub = try Stub<any GenericCache>(
            .method(
                .methodGenericParameter(index: 1),
                .methodGenericParameter(index: 0),
                returning: .concrete(Void.self)
            )
        )
        stub.when { $0.store(Match.equal("value"), forKey: Match.equal(7)) }.thenReturn(())

        let cache: any GenericCache = stub()
        cache.store("value", forKey: 7)

        stub.verify(.exactly(1)) {
            $0.store(Match.any(using: ""), forKey: Match.equal(7))
        }
    }

    @Test func negativeExplicitGenericParameterIndexFailsClosed() {
        expectUnsupportedProtocolShape(
            containing: "negative requirement-level generic parameter index"
        ) {
            _ = try Stub<any EventBus>(
                .method(
                    .methodGenericParameter(index: -1),
                    returning: .concrete(Void.self)
                )
            )
        }
    }

    @Test func sparseExplicitGenericParameterIndexFailsClosedWithoutAllocating() {
        expectUnsupportedProtocolShape(
            containing: "sparse requirement-level generic parameter indices"
        ) {
            _ = try Stub<any EventBus>(
                .method(
                    .methodGenericParameter(index: .max),
                    returning: .concrete(Void.self)
                )
            )
        }
    }

    @Test func protocolConstrainedGenericParameterIsRecorded() throws {
        let value = ExternalGenericConstraintValue()
        let stub =
            try Stub<
                any ProtocolConstrainedGenericRequirementProbe
            >()
        stub.when {
            $0.generic(Match.any(using: value))
        }.thenReturn(())

        let probe: any ProtocolConstrainedGenericRequirementProbe =
            stub()
        probe.generic(value)

        stub.verify {
            $0.generic(Match.any(using: value))
        }
    }

    @Test func multipleProtocolConstraintsAreRecorded() throws {
        let value = ExternalGenericConstraintValue()
        let stub =
            try Stub<
                any MultipleConstrainedGenericRequirementProbe
            >()
        stub.when {
            $0.generic(Match.any(using: value))
        }.thenReturn(())

        let probe: any MultipleConstrainedGenericRequirementProbe =
            stub()
        probe.generic(value)

        stub.verify {
            $0.generic(Match.any(using: value))
        }
    }

    @Test func classConstrainedGenericParameterUsesDirectReferenceTransport() throws {
        let value = ExternalGenericReferenceConstraintValue()
        let stub = try Stub<any ClassConstrainedGenericRequirementProbe>()
        stub.when {
            $0.generic(Match.any(using: value))
        }.thenReturn(())

        let probe: any ClassConstrainedGenericRequirementProbe = stub()
        probe.generic(value)

        stub.verify {
            $0.generic(Match.any(using: value))
        }
    }

    @Test func associatedSameTypeConstraintRetainsGenericTransport() throws {
        let value = ExternalStringRawValue.value
        let stub =
            try Stub<
                any SameTypeConstrainedGenericRequirementProbe
            >()
        stub.when {
            $0.generic(Match.equal(value))
        }.thenReturn(())

        let probe: any SameTypeConstrainedGenericRequirementProbe = stub()
        probe.generic(value)

        stub.verify {
            $0.generic(Match.equal(value))
        }
    }

    @Test func noncopyableGenericParameterFailsClosed() {
        expectUnsupportedProtocolShape(containing: "~Copyable") {
            _ = try Stub<any NoncopyableGenericRequirementProbe>()
        }
    }

    @Test func nonescapableGenericParameterFailsClosed() {
        expectUnsupportedProtocolShape(containing: "~Escapable") {
            _ = try Stub<any NonescapableGenericRequirementProbe>()
        }
    }

    @Test func consumingGenericParameterFailsClosed() {
        expectUnsupportedProtocolShape(
            containing: "consumes a requirement-level generic parameter"
        ) {
            _ = try Stub<any ConsumingGenericRequirementProbe>()
        }
    }

    @Test func asyncGenericParameterIsRecorded() async throws {
        let value = UserRegistered(userID: 42)
        let stub =
            try Stub<any AsyncGenericRequirementProbe>()
        await stub.when {
            await $0.publishAsync(Match.any(using: value))
        }.thenReturn(())

        let probe: any AsyncGenericRequirementProbe = stub()
        await probe.publishAsync(value)

        await stub.verify {
            await $0.publishAsync(Match.any(using: value))
        }
    }

    @Test func typedThrowingGenericParameterPreservesItsErrorChannel() throws {
        let accepted = UserRegistered(userID: 1)
        let rejected = UserRegistered(userID: -1)
        let failure = ExternalReferenceFixedFailure(code: 7)
        let stub =
            try Stub<
                any TypedThrowingGenericRequirementProbe
            >()
        stub.when {
            try $0.publishThrows(Match.equal(accepted))
        }.thenReturn(())
        stub.when {
            try $0.publishThrows(Match.equal(rejected))
        }.thenThrow(failure)

        let probe: any TypedThrowingGenericRequirementProbe =
            stub()
        try probe.publishThrows(accepted)
        #expect(throws: failure) {
            try probe.publishThrows(rejected)
        }

        stub.verify {
            try $0.publishThrows(Match.equal(rejected))
        }
    }

    @Test func genericMethodResultUsesTheCallersRuntimeType() throws {
        _ = RealGenericResultRequirementProbe()
        let stub = try Stub<any GenericResultRequirementProbe>()
        stub.when { $0.echo(Match.equal(7)) }.thenReturn(8)
        stub.when { $0.echo(Match.equal("input")) }.thenReturn("output")
        stub.when { $0.maybe(Match.equal(3)) }.thenReturn(4)
        stub.when { $0.maybe(Match.equal("none")) }.thenReturn(nil)
        stub.when(returning: 0) { $0.make() as Int }.thenReturn(42)
        stub.when {
            $0.second(Match.equal(1), Match.equal("a"))
        }.thenReturn("b")

        let probe: any GenericResultRequirementProbe = stub()
        #expect(probe.echo(7) == 8)
        #expect(probe.echo("input") == "output")
        #expect(probe.maybe(3) == 4)
        #expect(probe.maybe("none") == nil)
        #expect((probe.make() as Int) == 42)
        #expect(probe.second(1, "a") == "b")

        stub.verify {
            $0.echo(Match.equal(7))
        }
        stub.verify(returning: 0) {
            $0.make() as Int
        }
    }

    @Test func forwardingSpyDoesNotSupportAGenericParameter() {
        expectUnsupportedProtocolShape(
            containing: "Forwarding Spy does not support requirements with their own generic parameter"
        ) {
            _ = try Spy<any EventBus>(forwardingTo: RealEventBus())
        }
    }
}
