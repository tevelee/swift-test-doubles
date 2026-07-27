import Testing
import TestDoubles
import TestDoublesFixtures

/// End-to-end coverage for requirement-level generic parameters
/// (`func f<T>(...)`) using real-world-shaped protocols: an event bus, a
/// generic equality check, and a type-erased cache. See
/// `REQUIREMENT_GENERIC_SIGNATURES_DESIGN.md` for the ABI background.
@Suite struct GenericRequirementTests {
    private struct UserRegistered: Equatable {
        let userID: Int
    }

    private struct OrderShipped: Equatable {
        let orderID: String
    }

    @Test func automaticStubRecordsAPublishedEvent() throws {
        let captor = ArgumentCaptor<UserRegistered>()
        let stub = try Stub<any EventBus>()
        stub.when { $0.publish(captor.capture()) }.thenReturn(())

        let bus: any EventBus = stub()
        bus.publish(UserRegistered(userID: 42))

        #expect(captor.first == UserRegistered(userID: 42))
        stub.verify(.exactly(1)) {
            $0.publish(any(using: UserRegistered(userID: 0)))
        }
    }

    /// `any()` matches any value regardless of type, by design, the same way
    /// it does at an ordinary fixed-type argument position — it never claimed
    /// to discriminate types. At a requirement-level generic parameter,
    /// distinguishing which caller-supplied type a call used takes a matcher
    /// that itself performs a typed comparison, such as `equal(_:)`, whose
    /// internal cast naturally rejects a call carrying a different type.
    @Test func automaticStubDistinguishesDifferentEventTypesAtTheSameRequirement() throws {
        let stub = try Stub<any EventBus>()
        stub.when { $0.publish(equal(UserRegistered(userID: 1))) }.thenReturn(())
        stub.when { $0.publish(equal(UserRegistered(userID: 2))) }.thenReturn(())
        stub.when { $0.publish(equal(OrderShipped(orderID: "A-1"))) }.thenReturn(())

        let bus: any EventBus = stub()
        bus.publish(UserRegistered(userID: 1))
        bus.publish(OrderShipped(orderID: "A-1"))
        bus.publish(UserRegistered(userID: 2))

        stub.verify(.exactly(1)) { $0.publish(equal(UserRegistered(userID: 1))) }
        stub.verify(.exactly(1)) { $0.publish(equal(UserRegistered(userID: 2))) }
        stub.verify(.exactly(1)) { $0.publish(equal(OrderShipped(orderID: "A-1"))) }
    }

    @Test func automaticStubHandlesTwoArgumentsSharingOneGenericParameter() throws {
        let stub = try Stub<any EqualityChecker>()
        stub.when { $0.areEqual(equal(1), equal(1)) }.thenReturn(true)
        stub.when { $0.areEqual(equal("a"), equal("b")) }.thenReturn(false)

        let checker: any EqualityChecker = stub()

        #expect(checker.areEqual(1, 1) == true)
        #expect(checker.areEqual("a", "b") == false)
    }

    @Test func automaticStubHandlesTwoDistinctGenericParameters() throws {
        let stub = try Stub<any GenericCache>()
        stub.when { $0.store(equal("value"), forKey: equal(7)) }.thenReturn(())

        let cache: any GenericCache = stub()
        cache.store("value", forKey: 7)

        stub.verify(.exactly(1)) {
            $0.store(any(using: ""), forKey: equal(7))
        }
    }

    @Test func explicitRequirementDescribesAGenericParameterArgument() throws {
        let stub = try Stub<any EventBus>(
            .method(.methodGenericParameter(), returning: .concrete(Void.self))
        )
        stub.when { $0.publish(any(using: UserRegistered(userID: 0))) }.thenReturn(())

        let bus: any EventBus = stub()
        bus.publish(UserRegistered(userID: 9))

        stub.verify(.exactly(1)) {
            $0.publish(any(using: UserRegistered(userID: 0)))
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
