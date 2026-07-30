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

    @Test func classConstrainedGenericParameterFailsClosed() {
        expectUnsupportedProtocolShape(
            containing: "Class-constrained parameters use a direct reference ABI"
        ) {
            _ = try Stub<any ClassConstrainedGenericRequirementProbe>()
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

    @Test func combiningAGenericParameterWithAsyncFailsClosed() {
        expectUnsupportedProtocolShape(
            containing: "Async continuation transport has not been proven"
        ) {
            _ = try Stub<any AsyncGenericRequirementProbe>()
        }
    }

    @Test func combiningAGenericParameterWithTypedThrowsFailsClosed() {
        expectUnsupportedProtocolShape(
            containing: "Typed-throwing transport has not been proven"
        ) {
            _ = try Stub<any TypedThrowingGenericRequirementProbe>()
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
