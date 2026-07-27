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
