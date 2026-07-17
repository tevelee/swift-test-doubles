import Foundation
import Testing
@testable import TestDoubles

@Suite struct DelimitedSyntaxScannerTests {
    @Test func findsTheOuterArrowAcrossNestedFunctionsAndTypedThrows() throws {
        let spelling =
            "@Sendable (Swift.Result<(Swift.Int) -> Swift.String, Swift.Error>, [Swift.String: (Swift.Int) -> Swift.Bool]) async throws(Swift.Result<Swift.Int, Swift.Error>) -> [Swift.String]"
        let scanner = try #require(DelimitedSyntaxScanner(spelling))
        let arrow = try #require(scanner.topLevelRange(of: "->"))

        #expect(arrow == spelling.range(of: "->", options: .backwards))
        #expect(String(spelling[arrow.upperBound...]).trimmingCharacters(in: .whitespaces) == "[Swift.String]")
    }

    @Test func splitsNestedGenericsTuplesAndCollectionsOnlyAtTopLevel() throws {
        let arguments =
            "Swift.Result<(Swift.Int, [Swift.String]) -> Swift.Bool, Swift.Error>, [Swift.String: (Swift.Int, Swift.Double)], Swift.Set<Swift.String>"
        let scanner = try #require(DelimitedSyntaxScanner(arguments))

        #expect(
            scanner.components(separatedBy: ",") == [
                "Swift.Result<(Swift.Int, [Swift.String]) -> Swift.Bool, Swift.Error>",
                "[Swift.String: (Swift.Int, Swift.Double)]",
                "Swift.Set<Swift.String>"
            ]
        )
    }

    @Test func navigatesLoweredFunctionSyntax() throws {
        let lowered =
            "@callee_guaranteed (@in_guaranteed @callee_guaranteed (Swift.Int, Swift.String) -> (Swift.Bool), @in Swift.Result<Swift.Int, Swift.Error>) -> (@out Swift.String, @error any Swift.Error)"
        let scanner = try #require(DelimitedSyntaxScanner(lowered))
        let opening = try #require(lowered.firstIndex(of: "("))
        let closing = try #require(
            scanner.matchingClosingDelimiter(openingAt: opening)
        )
        let parameters = String(lowered[lowered.index(after: opening) ..< closing])
        let parameterScanner = try #require(DelimitedSyntaxScanner(parameters))

        #expect(parameterScanner.components(separatedBy: ",").count == 2)
        #expect(
            scanner.topLevelRange(of: "->")
                == lowered.range(of: "->", options: .backwards)
        )
    }

    @Test func rejectsDelimiterUnderflowAndUnterminatedInput() {
        #expect(DelimitedSyntaxScanner("Swift.Int)") == nil)
        #expect(DelimitedSyntaxScanner("Swift.Result<Swift.Int, Swift.Error") == nil)
        #expect(DelimitedSyntaxScanner("[(Swift.Int]") == nil)
        #expect(topLevelComponents(in: "Swift.Int], Swift.String") == nil)
    }
}
