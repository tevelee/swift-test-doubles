import Testing
@testable import TestDoubles

@Suite struct AssociatedTypedErrorTests {
    @Test func automaticDiscoverySupportsDirectAssociatedTypedErrors() throws {
        _ = RealAssociatedTypedThrowingProbe()
        typealias Probe = any AssociatedTypedThrowingProbe<ThrowingProbeError>
        let stub = try Stub<Probe>()
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(
            method.typedErrorType.map(ObjectIdentifier.init)
                == ObjectIdentifier(ThrowingProbeError.self)
        )
        #expect(method.typedErrorDependency == .associatedType(name: "Failure"))
        #expect(method.typedErrorUsesIndirectResultSlot)

        stub.when { try $0.load(equal(false)) }.thenReturn(42)
        stub.when { try $0.load(equal(true)) }.thenThrow(ThrowingProbeError(value: 7))
        let probe: Probe = stub()

        #expect(try probe.load(false) == 42)
        let error = #expect(throws: ThrowingProbeError.self) {
            _ = try probe.load(true)
        }
        #expect(error == ThrowingProbeError(value: 7))
    }

    @Test func explicitAssociatedTypedErrorDoesNotNeedLinkedConformer() throws {
        typealias ProbeStub = Stub<
            any ExplicitAssociatedTypedThrowingProbe<ThrowingProbeError>
        >
        let flag = ProbeStub.Requirement.Value.concrete(Bool.self)
        let result = ProbeStub.Requirement.Value.concrete(Int.self)
        let stub = try ProbeStub(
            .method(
                flag,
                returning: result,
                throwingAssociatedTypeNamed: "Failure"
            )
        )
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        #expect(method.typedErrorDependency == .associatedType(name: "Failure"))
        #expect(method.typedErrorUsesIndirectResultSlot)
        stub.when { try $0.load(any()) }.thenReturn(42)
        #expect(try stub().load(false) == 42)
    }

    @Test func explicitValidationDistinguishesConcreteAndAssociatedTypedErrors() {
        _ = RealAssociatedTypedThrowingProbe()
        typealias ProbeStub = Stub<
            any AssociatedTypedThrowingProbe<ThrowingProbeError>
        >

        expectStubError {
            _ = try ProbeStub(
                .method(
                    Bool.self,
                    returning: Int.self,
                    throwing: ThrowingProbeError.self
                )
            )
        } matching: { error in
            guard case .requirementMismatch(_, let index, let expected, let actual) = error else {
                return false
            }
            return index == 0
                && expected.contains("associated Failure")
                && actual.contains("associated Failure") == false
        }
    }

    @Test func wrappedAssociatedTypedErrorsRemainUnsupported() {
        _ = RealWrappedAssociatedTypedThrowingProbe()

        expectUnsupportedProtocolShape(containing: "Only a direct associated typed error") {
            _ = try Stub<
                any WrappedAssociatedTypedThrowingProbe<ThrowingProbeError>
            >()
        }
    }
}
