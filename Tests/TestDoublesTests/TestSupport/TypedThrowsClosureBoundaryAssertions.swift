import TestDoublesRuntime
import Testing

@discardableResult
func expectLinuxX86TypedThrowsClosureBoundary(
    _ operation: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) -> Bool {
    #if os(Linux) && arch(x86_64)
        expectUnsupportedProtocolShape(
            containing: "Typed-throws closure values are unavailable on Linux x86_64",
            sourceLocation: sourceLocation,
            operation
        )
        return true
    #else
        return false
    #endif
}

@discardableResult
func expectExtendedAutomaticClosureBoundary(
    _ operation: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) -> Bool {
    #if os(Linux) && arch(x86_64)
        expectLinuxX86TypedThrowsClosureBoundary(operation, sourceLocation: sourceLocation)
    #else
        expectUnsupportedProtocolShape(
            containing: "Global-actor functions require an executor-preserving bridge whose actor identity can be verified",
            sourceLocation: sourceLocation,
            operation
        )
    #endif
    return true
}

/// True when this process's extended function-type flags are trustworthy
/// enough to automatically bridge a closure shaped like `type` (a closure
/// that combines a `sending` parameter with a `sending` result, such as
/// `ExternalSendingClosure`). Swift 6.3 does not reliably surface those
/// flags on Linux: the raw word Echo reads back for this shape can hold bit
/// patterns no compiler would emit, and the value differs by process, so
/// this is checked at runtime rather than gated by `#if os(Linux)` — a
/// caller should skip gracefully when this is `false` and test normally
/// otherwise, including on Linux runs where the flags do come back clean.
func sendingClosureAutomaticBridgeIsReliable(for type: Any.Type) -> Bool {
    FunctionReabstraction.automaticArgumentUnsupportedReason(for: type) == nil
        && FunctionReabstraction.automaticResultUnsupportedReason(for: type) == nil
}
