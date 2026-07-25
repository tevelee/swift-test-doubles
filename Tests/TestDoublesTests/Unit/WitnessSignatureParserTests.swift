import Testing
@testable import TestDoubles

@Suite struct WitnessSignatureParserTests {
    @Test func genericProtocolMethodNameExcludesItsOwnGenericClause() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.fetch<A>(A1) -> A1 in conformance test2.S<A> : test2.P in test2",
                kind: .method
            )
        )
        #expect(signature.name == "fetch(_:)")
    }

    @Test func methodNameDotsInsideGenericArgumentsAreNotSplitOn() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.take(Swift.Int) -> Swift.Int in conformance test2.S : test2.P in test2",
                kind: .method
            )
        )
        #expect(signature.name == "take(_:)")
    }

    @Test func nestedWrapperPrefixesAreFullyStripped() throws {
        let signature = try #require(
            parseWitnessSignature(
                "dispatch thunk of protocol witness for test2.P.fetch(Swift.Int) -> Swift.Int in conformance test2.S : test2.P in test2",
                kind: .method
            )
        )
        #expect(signature.name == "fetch(_:)")
    }
}
