import Testing

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    func requireStandardErrorDiagnostic(
        from result: ExitTest.Result,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> String {
        try #require(
            String(bytes: result.standardErrorContent, encoding: .utf8),
            sourceLocation: sourceLocation
        )
    }
#endif
