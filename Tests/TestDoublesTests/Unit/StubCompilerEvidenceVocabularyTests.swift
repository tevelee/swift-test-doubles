import TestDoubles
import Testing

protocol CompilerEvidenceProbe {
    func label(for value: Int) -> String
}

struct LinkedCompilerEvidenceProbe: CompilerEvidenceProbe {
    func label(for value: Int) -> String { "live-\(value)" }
}

protocol CompilerEvidenceActorProbe: Actor {
    func ping() async
}

actor CompilerEvidenceActorProbeStubConformer:
    CompilerEvidenceActorProbe,
    ManualStubConformer
{
    let stub: CompiledStub<CompilerEvidenceActorProbeStubConformer>

    init(stub: CompiledStub<CompilerEvidenceActorProbeStubConformer>) {
        self.stub = stub
    }

    func ping() async {
        await stub.call()
    }
}

@Suite struct StubCompilerEvidenceVocabularyTests {
    @Test func explicitManifestCarriesACompilerDescribedRuntimeRecipe() {
        typealias Probe = any CompilerEvidenceProbe
        let support = StubRequirementSupport(
            declaringProtocol: "CompilerEvidenceProbe",
            name: "label(for:)",
            kind: .method,
            declarationIndex: 0,
            runtimeEligibility: .compilerDescribed,
            compiledEligibility: .compiledConformer
        )
        let manifest = StubCompilerEvidence<Probe>(
            runtimeConstruction: .requirements([
                .method(Int.self, returning: String.self)
            ]),
            compiledFallbackEligibility: .compiledConformer,
            sourceSupport: StubSourceSupportReport(
                protocolName: "CompilerEvidenceProbe",
                requirements: [support]
            )
        )

        #expect(manifest.runtimeEligibility == .compilerDescribed)
        #expect(manifest.compiledFallbackEligibility == .compiledConformer)
        #expect(manifest.sourceSupport.runtimeIsCompilerDescribed)
        #expect(manifest.sourceSupport.hasCompleteCompiledFallback)
        #expect(manifest.sourceSupport.needsRuntimeDiscovery == false)
        switch manifest.runtimeConstruction {
            case .requirements(let requirements):
                #expect(requirements.count == 1)
            default:
                Issue.record("Expected an explicit compiler-described recipe.")
        }
    }

    @Test func automaticDiscoveryDoesNotClaimCompilerProof() {
        typealias Probe = any CompilerEvidenceProbe
        let manifest = StubCompilerEvidence<Probe>(
            runtimeConstruction: .automaticDiscovery,
            compiledFallbackEligibility: .unavailable(
                reason: "No generated conformer is linked."
            ),
            sourceSupport: StubSourceSupportReport(
                protocolName: "CompilerEvidenceProbe",
                requirements: [
                    StubRequirementSupport(
                        declaringProtocol: "CompilerEvidenceProbe",
                        name: "label(for:)",
                        kind: .method,
                        declarationIndex: 0,
                        runtimeEligibility: .requiresRuntimeDiscovery,
                        compiledEligibility: .unavailable(
                            reason: "No generated conformer is linked."
                        )
                    )
                ]
            )
        )

        #expect(manifest.runtimeEligibility == .requiresRuntimeDiscovery)
        #expect(manifest.sourceSupport.runtimeIsCompilerDescribed == false)
        #expect(manifest.sourceSupport.needsRuntimeDiscovery)
        #expect(manifest.sourceSupport.hasCompleteCompiledFallback == false)
    }

    @Test func actualConstructionReportProjectsRuntimeGeneration() throws {
        _ = LinkedCompilerEvidenceProbe()
        let stub = try Stub<any CompilerEvidenceProbe>()

        #expect(stub.constructionReport.protocolName.contains("CompilerEvidenceProbe"))
        #expect(stub.constructionReport.strategy == .runtimeGenerated)
        #expect(stub.constructionReport.runtimeFailure == nil)
        #expect(stub.constructionReport.runtimeFailureDescription == nil)
    }

    @Test func actualConstructionReportPreservesCompiledFallbackReason() {
        let stub = Stub<any CompilerEvidenceActorProbe>(
            fallingBackTo: CompilerEvidenceActorProbeStubConformer.self,
            erasingWith: { $0 }
        )

        #expect(stub.constructionReport.strategy == .compiledFallback)
        #expect(stub.constructionReport.runtimeFailure == stub.runtimeFallbackReason)
        #expect(
            stub.constructionReport.runtimeFailureDescription?.contains(
                "Actor protocols require a genuine actor instance"
            ) == true
        )
    }
}
