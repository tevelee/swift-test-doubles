import TestDoublesRuntime
import TestDoublesRuntimeMetadata
import Testing
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

    @Test func variadicParametersResolveAsOneArrayArgument() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.tally(test2.Value...) -> Swift.UInt64 in conformance test2.S : test2.P in test2",
                kind: .method
            )
        )
        #expect(signature.name == "tally(_:)")
        #expect(signature.argumentTypeNames == ["Swift.Array<test2.Value>"])
    }

    @Test func autoclosureParametersRemainVisibleToConstructionValidation() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.record(@autoclosure @escaping () -> Swift.String) -> () in conformance test2.S : test2.P in test2",
                kind: .method
            )
        )
        #expect(signature.argumentIsAutoclosure == [true])
    }

    @Test func rawAutoclosureManglingRetainsEscapingConvention() {
        #expect(
            containsNonescapingAutoclosure(
                in: "$s16ConsumerFixtures22AutoclosureDeliveryLogP6recordyySSyXAFTj"
            ) == false
        )
        #expect(
            containsNonescapingAutoclosure(
                in: "$s16ConsumerFixtures27EagerAutoclosureDeliveryLogP6recordyySSyXKFTj"
            )
        )
        #expect(
            containsNonescapingAutoclosure(
                in: "$s16ConsumerFixtures34EagerIntegerAutoclosureDeliveryLogP6recordyySiyXKtF"
            )
        )
        #expect(
            containsNonescapingAutoclosure(
                in: "$s16ConsumerFixtures25XKFAutoclosureDeliveryLogP6recordyySSyXAFTj"
            ) == false
        )
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

    // Local-declaration strings below are real demanglings from a compiled
    // binary.

    @Test func localProtocolMethodDropsItsDeclarationContext() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for read(path: Swift.String) throws -> Foundation.Data in P1 #1 in test2.topLevelFunction() -> () in conformance S1 #1 in test2.topLevelFunction() -> () : P1 #1 in test2.topLevelFunction() -> () in test2",
                kind: .method
            )
        )
        #expect(signature.name == "read(path:)")
        #expect(signature.argumentTypeNames == ["Swift.String"])
        #expect(signature.returnTypeName == "Foundation.Data")
        #expect(signature.isThrowing)
    }

    @Test func localProtocolMethodInsideAMethodDropsItsDeclarationContext() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for ping() -> Swift.Int in Deep #1 in static test2.Host.inner() -> () in conformance DeepImpl #1 in static test2.Host.inner() -> () : Deep #1 in static test2.Host.inner() -> () in test2",
                kind: .method
            )
        )
        #expect(signature.name == "ping()")
        #expect(signature.returnTypeName == "Swift.Int")
    }

    @Test func closureLocalProtocolMethodDropsItsDeclarationContext() throws {
        let context =
            "closure #1 () -> () in variable initialization expression of test2.closure : () -> ()"
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for go() -> Swift.Int in InClosure #1 in \(context)"
                    + " in conformance InClosureImpl #1 in \(context)"
                    + " : InClosure #1 in \(context) in test2",
                kind: .method
            )
        )
        #expect(signature.name == "go()")
        #expect(signature.returnTypeName == "Swift.Int")
    }

    @Test func localProtocolGenericMethodDropsItsDeclarationContext() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for generic<A>(A1) -> A1 in P4 #1 in test2.topLevelFunction() -> () in conformance S4 #1 in test2.topLevelFunction() -> () : P4 #1 in test2.topLevelFunction() -> () in test2",
                kind: .method
            )
        )
        #expect(signature.name == "generic(_:)")
    }

    @Test func localProtocolAccessorDropsItsDeclarationContext() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for count.getter : Swift.Int in P2 #1 in test2.topLevelFunction() -> () in conformance S2 #1 in test2.topLevelFunction() -> () : P2 #1 in test2.topLevelFunction() -> () in test2",
                kind: .getter
            )
        )
        #expect(signature.name == "count")
        #expect(signature.returnTypeName == "Swift.Int")
    }

    @Test func localProtocolSubscriptAccessorDropsItsDeclarationContext() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for subscript.getter : (Swift.Int) -> Swift.String in P2 #1 in test2.topLevelFunction() -> () in conformance S2 #1 in test2.topLevelFunction() -> () : P2 #1 in test2.topLevelFunction() -> () in test2",
                kind: .getter
            )
        )
        #expect(signature.name == "subscript")
        #expect(signature.argumentTypeNames == ["Swift.Int"])
        #expect(signature.returnTypeName == "Swift.String")
    }

    @Test func localResultTypeIsLeftForTheTypeParserToReject() {
        #expect(
            parseWitnessSignature(
                "protocol witness for make() -> Box #1 in test2.topLevelFunction() -> () in P3 #1 in test2.topLevelFunction() -> () in conformance S3 #1 in test2.topLevelFunction() -> () : P3 #1 in test2.topLevelFunction() -> () in test2",
                kind: .method
            ) == nil
        )
    }

    @Test func fileScopeSignatureMentioningInIsUnchanged() throws {
        let signature = try #require(
            parseWitnessSignature(
                "protocol witness for test2.P.insert(into: test2.Container) -> test2.Inline in conformance test2.S : test2.P in test2",
                kind: .method
            )
        )
        #expect(signature.name == "insert(into:)")
        #expect(signature.argumentTypeNames == ["test2.Container"])
        #expect(signature.returnTypeName == "test2.Inline")
    }
}
