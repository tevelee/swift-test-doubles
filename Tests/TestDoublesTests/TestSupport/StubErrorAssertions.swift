import Testing
@testable import TestDoubles

func expectStubError(
    _ operation: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation,
    matching predicate: (StubError) -> Bool
) {
    do {
        try operation()
        Issue.record("Expected StubError", sourceLocation: sourceLocation)
    } catch let error as StubError {
        #expect(
            predicate(error),
            "Unexpected StubError: \(error)",
            sourceLocation: sourceLocation
        )
    } catch {
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
    }
}

/// Expects `operation` to throw `StubError.unsupportedProtocolShape`,
/// optionally requiring `fragment` to appear in the diagnostic reason.
func expectUnsupportedProtocolShape(
    containing fragment: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () throws -> Void
) {
    expectStubError(operation, sourceLocation: sourceLocation) { error in
        guard case .unsupportedProtocolShape(_, let reason) = error else {
            return false
        }
        guard let fragment else { return true }
        return reason.contains(fragment)
    }
}
