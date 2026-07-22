import TestDoublesFixtures
import Testing
@testable import TestDoubles

private func useLinkedAssociatedFunctionProbe(
    _ value: any ExternalAssociatedFunctionProbe<Int>
) -> String {
    value.apply { "\($0)" }
}

@Suite struct AssociatedFunctionTypeTests {
    @Test func automaticDiscoveryRejectsAssociatedFunctionValuesBeforeTransport() {
        #expect(
            useLinkedAssociatedFunctionProbe(
                RealExternalAssociatedFunctionProbe()
            ) == "21"
        )

        expectUnsupportedProtocolShape(
            containing: "fixed two-word outer layout does not determine the inner generic calling convention"
        ) {
            _ = try Stub<any ExternalAssociatedFunctionProbe<Int>>()
        }
    }

    @Test func explicitSchemasCannotEraseAssociatedFunctionDependency() {
        _ = RealExternalAssociatedFunctionProbe()
        typealias ProbeStub = Stub<any ExternalAssociatedFunctionProbe<Int>>
        let value = ProbeStub.Requirement.Value.self

        expectUnsupportedProtocolShape(
            containing: "Automatic and explicit construction fail closed before transport"
        ) {
            _ = try ProbeStub(
                .method(
                    value.concrete(((Int) -> String).self),
                    returning: value.concrete(String.self)
                ),
                .method(
                    value.concrete(Int.self),
                    returning: value.concrete(((Int) -> Int).self)
                ),
                .method(
                    value.concrete((([Int]?) -> String).self),
                    returning: value.concrete(String.self)
                )
            )
        }
    }

    @Test func associatedFunctionShapesFailClosedBeforeTransport() {
        _ = RealExternalNonescapingAssociatedFunctionProbe()
        _ = RealExternalAsyncAssociatedFunctionProbe()
        _ = RealExternalThrowingAssociatedFunctionProbe()
        _ = RealExternalInoutAssociatedFunctionProbe()
        _ = RealExternalTypedThrowingAssociatedFunctionProbe()

        let operations: [() throws -> Void] = [
            {
                _ = try Stub<
                    any ExternalNonescapingAssociatedFunctionProbe<Int>
                >()
            },
            {
                _ = try Stub<any ExternalAsyncAssociatedFunctionProbe<Int>>()
            },
            {
                _ = try Stub<
                    any ExternalThrowingAssociatedFunctionProbe<Int>
                >()
            },
            {
                _ = try Stub<any ExternalInoutAssociatedFunctionProbe<Int>>()
            },
            {
                _ = try Stub<
                    any ExternalTypedThrowingAssociatedFunctionProbe<
                        ExternalAssociatedFunctionError
                    >
                >()
            }
        ]

        for operation in operations {
            expectUnsupportedProtocolShape(
                containing: "associated-dependent function value"
            ) {
                try operation()
            }
        }
    }
}
