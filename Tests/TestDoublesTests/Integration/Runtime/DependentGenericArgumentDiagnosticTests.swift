import Testing
import TestDoubles

struct DiagnosticEndpoint<Response>: Sendable {
    var path: String
}

protocol DiagnosticAPIClient {
    func send<Response>(_ endpoint: DiagnosticEndpoint<Response>) -> Response?
}

struct LiveDiagnosticAPIClient: DiagnosticAPIClient {
    func send<Response>(_ endpoint: DiagnosticEndpoint<Response>) -> Response? { nil }
}

/// A generic nominal built from a method generic parameter is outside the
/// runtime boundary; the diagnostic says so and points at the compiled route.
@Suite struct DependentGenericArgumentDiagnosticTests {
    @Test func explainsMethodGenericParametersInsideGenericTypes() {
        do {
            _ = try Stub<any DiagnosticAPIClient>(discoveringFrom: LiveDiagnosticAPIClient())
            Issue.record("Expected construction to fail")
        } catch {
            let description = String(describing: error)
            #expect(description.contains("method generic parameter"))
            #expect(description.contains("ManualStubBuildPlugin"))
        }
    }
}
