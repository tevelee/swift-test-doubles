import Echo
import Testing

@testable import TestDoubles

private final class PointerAuthReference {}

@Suite
struct FunctionPointerAuthenticationTests {
    @Test
    func stableFunctionDiscriminatorsMatchTheSwiftRuntime() throws {
        let discriminators = try #require(
            FunctionReabstraction.pointerAuthDiscriminators(
                for: (@Sendable (Int) -> Int).self
            )
        )

        #expect(discriminators.direct == 18_587)
        #expect(discriminators.generic == 55_683)
    }

    @Test
    func supportedRuntimeKindsHaveCanonicalSpellings() {
        #expect(pointerAuthTypeSpelling((Int, Double).self) == "-")
        #expect(pointerAuthTypeSpelling([Int].self) == "$sSa")
        #expect(pointerAuthTypeSpelling(PointerAuthReference.self) == "-class")
        #expect(pointerAuthTypeSpelling(PointerAuthReference?.self) == "-class")
        #expect(
            pointerAuthTypeSpelling(((Int) -> String).self)?
                .hasPrefix("(function:1:") == true
        )
    }

    @Test
    func functionIntrospectionHandlesNullaryAndMixedParameters() throws {
        let nullary = try #require(
            reflect((() -> Int).self) as? FunctionMetadata
        )
        #expect(safeFunctionParameterTypes(nullary).isEmpty)
        #expect(functionLoweredParameterCount(nullary) == 0)

        let mixed = try #require(
            reflect(((Int, Double) async -> String).self) as? FunctionMetadata
        )
        let parameters = safeFunctionParameterTypes(mixed)
        #expect(parameters.count == 2)
        #expect(ObjectIdentifier(parameters[0]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(parameters[1]) == ObjectIdentifier(Double.self))
        #expect(functionLoweredParameterCount(mixed) == 2)
        #expect(functionIsAsync(mixed))
    }
}
