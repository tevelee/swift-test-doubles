import TestDoublesRuntime
import TestDoublesRuntimeMetadata
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

    @Test func borrowAccessorMarkerIsRecognized() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.value.borrow : Swift.Int in conformance test2.S : test2.P in test2",
                kind: .readCoroutine
            )
        )
        #expect(signature.name == "value")
        #expect(signature.returnTypeName == "Swift.Int")
    }

    @Test func readTwoAccessorMarkerIsStillRecognized() throws {
        // The live Swift 6.3.3 toolchain demangles yield_once_2 read
        // witnesses this way (see ReadAccessorTests fixtures); it isn't a
        // dead marker even though upstream main's current NodePrinter.cpp
        // doesn't have a distinct node kind for it.
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.value.read2 : Swift.Int in conformance test2.S : test2.P in test2",
                kind: .readCoroutine
            )
        )
        #expect(signature.name == "value")
        #expect(signature.returnTypeName == "Swift.Int")
    }
}
