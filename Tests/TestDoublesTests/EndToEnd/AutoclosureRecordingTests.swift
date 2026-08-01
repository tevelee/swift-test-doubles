import TestDoubles
import TestDoublesFixtures
import Testing

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct AutoclosureRecordingExitTests {
        @Test func directMatcherInsideAutoclosureExplainsHowToPrebindIt() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = RealExternalAutoclosureParameterService()
                let stub = try Stub<any ExternalAutoclosureParameterService>()
                _ = stub.when { $0.evaluate(Match.any()) }
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("@autoclosure") == true)
            #expect(diagnostic.contains("closure-typed Match expression") == true)
        }
    }
#endif
