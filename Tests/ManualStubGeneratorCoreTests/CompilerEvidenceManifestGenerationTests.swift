import Testing
@testable import ManualStubGeneratorCore

@Suite struct CompilerEvidenceManifestGenerationTests {
    @Test func emitsCompilerDescribedRequirementsAndSourceSupport() throws {
        let output = try ManualStubGenerator(
            protocolName: "Lookup",
            source: """
                protocol Lookup {
                    func value(for key: String, limit: Int) async throws -> Data
                    var count: Int { get set }
                    subscript(_ section: Int, key key: String) -> Data { get set }
                }
                """
        ).render(importingTestDoubles: false)

        #expect(output.contains("static let compilerEvidence: StubCompilerEvidence<StubbedProtocol>"))
        #expect(
            output.contains(
                ".method(String.self, Int.self, returning: Data.self, isThrowing: true, isAsync: true)"
            )
        )
        #expect(output.contains(".getter(Int.self)"))
        #expect(output.contains(".setter(Int.self)"))
        #expect(
            output.contains(
                ".subscriptGetter(indexedBy: Int.self, String.self, returning: Data.self)"
            )
        )
        #expect(
            output.contains(
                ".subscriptSetter(indexedBy: Int.self, String.self, assigning: Data.self)"
            )
        )
        #expect(output.contains("name: \"value(for:limit:)\""))
        #expect(output.contains("name: \"subscript\""))
        #expect(output.contains("runtimeEligibility: .compilerDescribed"))
    }

    @Test func fallsBackToDiscoveryWhenSourceCannotDescribeExactTransport() throws {
        let output = try ManualStubGenerator(
            protocolName: "Mutator",
            source: """
                protocol Mutator {
                    func count() -> Int
                    func mutate(_ value: inout Int)
                }
                """
        ).render(importingTestDoubles: false)

        #expect(output.contains("runtimeConstruction: .automaticDiscovery"))
        #expect(output.contains("name: \"count()\""))
        #expect(output.contains("runtimeEligibility: .compilerDescribed"))
        #expect(output.contains("runtimeEligibility: .requiresRuntimeDiscovery"))
        #expect(output.contains("compiledFallbackEligibility: .generatedConformer"))
    }

    @Test func routesActorProtocolsDirectlyToTheirCompiledConformer() throws {
        let output = try ManualStubGenerator(
            protocolName: "ActorSource",
            source: """
                protocol ActorSource: Actor {
                    func load(_ identifier: Int) -> String
                }
                """
        ).render(importingTestDoubles: false)

        #expect(
            output.contains(
                "runtimeConstruction: .unavailable(reason: \"Actor protocols require a genuine actor instance.\")"
            )
        )
        #expect(output.contains("compiledFallbackEligibility: .generatedConformer"))
    }
}
