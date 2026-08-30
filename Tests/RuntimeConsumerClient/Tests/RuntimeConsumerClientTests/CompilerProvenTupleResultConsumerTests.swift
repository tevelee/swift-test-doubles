import ConsumerFixtures
import Foundation
import TestDoubles
import Testing

@Suite struct CompilerProvenTupleResultConsumerTests {
    @Test func unprovenCustomTupleLeafStillFailsClosed() {
        let error = #expect(throws: StubError.self) {
            _ = try Stub<any UnprovenCustomTupleResultSource>()
        }
        #expect(error?.description.contains("ABI-uncertain result") == true)
        #expect(
            error?.description.contains(
                "Tuple members are lowered independently"
            ) == true
        )
    }

    @Test func automaticConstructionTransportsDirectFoundationTupleLeaves() throws {
        let stub = try Stub<any CompilerProvenFoundationTupleSource>()
        let expectedDataAndCount = (Data([2, 3, 5]), 7)
        let expectedDataAndRatio = (Data([11, 13]), 17.0)

        stub.when(returning: (Data(), 0)) { $0.dataAndCount() }
            .thenReturn(expectedDataAndCount)
        stub.when(returning: (Data(), 0.0)) { $0.dataAndRatio() }
            .thenReturn(expectedDataAndRatio)

        let source = stub()
        let dataAndCount = source.dataAndCount()
        let dataAndRatio = source.dataAndRatio()
        #expect(dataAndCount.0 == expectedDataAndCount.0)
        #expect(dataAndCount.1 == expectedDataAndCount.1)
        #expect(dataAndRatio.0 == expectedDataAndRatio.0)
        #expect(dataAndRatio.1 == expectedDataAndRatio.1)
        stub.verify { $0.dataAndCount() }
        stub.verify { $0.dataAndRatio() }
    }

    #if compiler(>=6.4)
        @Test func automaticConstructionTransportsIndirectFoundationTupleLeaf() throws {
            let stub = try Stub<any CompilerProvenFoundationTupleSource>()
            let identifier = UUID(
                uuidString: "00000000-0000-0000-0000-000000000019"
            )!

            stub.when(returning: (UUID(), 0)) { $0.identifierAndCount() }
                .thenReturn((identifier, 23))

            let result = stub().identifierAndCount()
            #expect(result.0 == identifier)
            #expect(result.1 == 23)
            stub.verify { $0.identifierAndCount() }
        }

        @Test func automaticConstructionTransportsMultipleIndirectTupleLeavesAndArgument() throws {
            let stub = try Stub<any CompilerProvenFoundationTupleSource>()
            let identifier = UUID(
                uuidString: "00000000-0000-0000-0000-000000000029"
            )!
            let date = Date(timeIntervalSinceReferenceDate: 31)

            stub.when(returning: (UUID(), Date(), 0)) {
                try $0.identifierAndDate(for: Match.equal(37))
            }.thenReturn((identifier, date, 41))

            let result = try stub().identifierAndDate(for: 37)
            #expect(result.0 == identifier)
            #expect(result.1 == date)
            #expect(result.2 == 41)
            stub.verify {
                try $0.identifierAndDate(for: Match.equal(37))
            }
        }

        @Test func automaticConstructionTransportsNestedTupleLeaves() throws {
            let stub = try Stub<any CompilerProvenFoundationTupleSource>()
            let data = Data([43, 47])
            let identifier = UUID(
                uuidString: "00000000-0000-0000-0000-000000000053"
            )!

            stub.when(returning: (Data(), (UUID(), 0))) {
                $0.nestedFoundationValues()
            }.thenReturn((data, (identifier, 59)))

            let result = stub().nestedFoundationValues()
            #expect(result.0 == data)
            #expect(result.1.0 == identifier)
            #expect(result.1.1 == 59)
        }

        @Test func automaticConstructionTransportsAsyncIndirectTupleLeaf() async throws {
            let stub = try Stub<any CompilerProvenFoundationTupleSource>()
            let identifier = UUID(
                uuidString: "00000000-0000-0000-0000-000000000061"
            )!

            await stub.when(returning: (UUID(), 0)) {
                await $0.asyncIdentifierAndCount(for: Match.equal(67))
            }.thenReturn((identifier, 71))

            let result = await stub().asyncIdentifierAndCount(for: 67)
            #expect(result.0 == identifier)
            #expect(result.1 == 71)
        }

        @Test func forwardingSpyTransportsMixedFoundationTupleResult() throws {
            let spy = try Spy<any ForwardingFoundationTupleSource>(
                forwardingTo: LiveForwardingFoundationTupleSource()
            )
            let overrideIdentifier = UUID(
                uuidString: "00000000-0000-0000-0000-000000000073"
            )!
            spy.when(returning: (UUID(), 0)) {
                $0.identifierAndCount(for: Match.equal(79))
            }.thenReturn((overrideIdentifier, 83))

            let forwarded = spy().identifierAndCount(for: 89)
            let overridden = spy().identifierAndCount(for: 79)
            #expect(
                forwarded.0
                    == UUID(
                        uuidString: "00000000-0000-0000-0000-000000000059"
                    )!
            )
            #expect(forwarded.1 == 89)
            #expect(overridden.0 == overrideIdentifier)
            #expect(overridden.1 == 83)
            spy.verifyOnlyForwarded {
                _ = $0.identifierAndCount(for: 89)
            }
        }
    #endif
}
