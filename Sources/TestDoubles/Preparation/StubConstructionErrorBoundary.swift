/// Runs a runtime test-double construction operation while preserving the
/// public `StubError` failure contract.
///
/// Construction helpers predate typed throws but are required to report only
/// `StubError`. Any other error indicates an internal invariant violation and
/// fails closed instead of escaping through the public API as `any Error`.
func withStubConstructionError<Result>(
    for protocolType: Any.Type,
    _ operation: () throws -> Result
) throws(StubError) -> Result {
    do {
        return try operation()
    } catch let error as StubError {
        throw error
    } catch {
        preconditionFailure(
            "[TestDoubles] Construction for '\(String(reflecting: protocolType))' "
                + "threw unexpected internal error type "
                + "'\(String(reflecting: Swift.type(of: error)))': \(error)"
        )
    }
}

enum TestDoubleConstructionKind: String {
    case dummy
    case spy
    case stub
}

func constructTestDoubleOrFail<Result>(
    _ kind: TestDoubleConstructionKind,
    for protocolType: Any.Type,
    _ operation: () throws(StubError) -> Result
) -> Result {
    do {
        return try operation()
    } catch {
        fatalError(
            "[TestDoubles] Could not construct a \(kind.rawValue) for "
                + "'\(String(reflecting: protocolType))': \(error)"
        )
    }
}
