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
