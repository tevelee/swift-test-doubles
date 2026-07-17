import Testing
@testable import TestDoubles

@Suite struct DemangledTypeSyntaxTests {
    @Test func sourceFunctionPreservesNestedGenericAndTypedThrowsSyntax() throws {
        let spelling =
            "@Sendable (Swift.Result<(Swift.Int) -> Swift.String, Swift.Error>, @autoclosure () -> Swift.Int) async throws(Swift.Result<Swift.Int, Swift.Error>) -> [Swift.String: (Swift.Int) -> Swift.Bool]"
        let syntax = try #require(DemangledTypeSyntax(spelling))
        guard case .function(let function) = syntax else {
            Issue.record("Expected source-level function syntax")
            return
        }

        #expect(syntax.canonicalSpelling == spelling)
        #expect(function.parameters.count == 2)
        #expect(function.parameters[0].type.canonicalSpelling.contains("Swift.Result"))
        #expect(function.parameters[1].isAutoclosure)
        #expect(function.effects.isAsync)
        #expect(function.effects.isThrowing)
        #expect(
            function.effects.thrownError?.canonicalSpelling
                == "Swift.Result<Swift.Int, Swift.Error>"
        )
        #expect(
            function.result.canonicalSpelling
                == "[Swift.String: (Swift.Int) -> Swift.Bool]"
        )
    }

    @Test func loweredFunctionKeepsNestedFunctionAndErrorResultsDistinct() throws {
        let spelling =
            "@escaping @callee_guaranteed @Sendable "
            + "(@in_guaranteed Swift.Result<Swift.Int, Swift.Error>, "
            + "@owned @callee_guaranteed (@unowned Swift.Int) "
            + "-> (@owned Swift.String, @error @owned Swift.Error)) "
            + "-> (@owned Swift.String, @error @owned Swift.Error)"
        let syntax = try #require(LoweredFunctionSyntax(spelling))

        #expect(syntax.canonicalSpelling == spelling)
        #expect(syntax.parameters.count == 2)
        #expect(syntax.isSendable)
        #expect(syntax.isThrowing)
        guard case .function(let nested) = syntax.parameters[1].type else {
            Issue.record("Expected a distinct nested lowered function node")
            return
        }
        #expect(nested.parameters.count == 1)
        #expect(nested.isThrowing)
    }

    @Test func loweredGenericSubstitutionClauseIsValidatedAndPreserved() throws {
        let spelling =
            "@escaping @callee_guaranteed @substituted <A, B where A: ~Swift.Copyable, B: ~Swift.Copyable> (@in_guaranteed A) -> (@out B) for <Swift.IntSwift.String>"
        let syntax = try #require(LoweredFunctionSyntax(spelling))

        #expect(syntax.canonicalSpelling == spelling)
        #expect(syntax.isGeneric)
        #expect(syntax.parameters.count == 1)
        #expect(syntax.isThrowing == false)
    }

    @Test func malformedAndUnsupportedShapesFailClosed() {
        #expect(DemangledTypeSyntax("@Sendable Swift.Int -> Swift.String") == nil)
        #expect(
            DemangledTypeSyntax(
                "@Sendable (Swift.Int) throws(Swift.Error -> Swift.String"
            ) == nil
        )
        #expect(
            LoweredFunctionSyntax(
                "@callee_guaranteed (@in Swift.Int] -> (@out Swift.String)"
            ) == nil
        )
        #expect(
            LoweredFunctionSyntax(
                "@callee_guaranteed (@in Swift.Int) -> (@out Swift.String) trailing"
            ) == nil
        )
    }
}
