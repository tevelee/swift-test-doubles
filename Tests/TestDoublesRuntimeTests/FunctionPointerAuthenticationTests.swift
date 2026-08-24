import EchoRuntimeReflection
import Testing

@testable import TestDoublesRuntime

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
        let nullary = try #require(FunctionTypeInfo(reflecting: (() -> Int).self))
        #expect(nullary.parameters.isEmpty)
        #expect(nullary.parameters.count == 0)

        let mixed = try #require(
            FunctionTypeInfo(reflecting: ((Int, Double) async -> String).self)
        )
        let parameters = mixed.parameters
        #expect(parameters.count == 2)
        #expect(ObjectIdentifier(parameters[0].type) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(parameters[1].type) == ObjectIdentifier(Double.self))
        #expect(mixed.parameters.count == 2)
        #expect(mixed.effects.isAsync)
    }
}
