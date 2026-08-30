import Foundation
import Testing
@testable import TestDoubles

private protocol EvidenceParameterizedDataSource {
    func read(path: String) throws -> Data
}

private struct EvidenceParameterizedDataSourceStubConformer:
    EvidenceParameterizedDataSource, AutomaticStubConformer
{
    typealias StubbedProtocol = any EvidenceParameterizedDataSource

    let stub: CompiledStub<Self>

    static let compilerEvidence = StubCompilerEvidence<StubbedProtocol>(
        runtimeConstruction: .requirements([
            .method(String.self, returning: Data.self, isThrowing: true)
        ]),
        compiledFallbackEligibility: .generatedConformer,
        sourceSupport: StubSourceSupportReport(
            protocolName: "EvidenceParameterizedDataSource",
            requirements: [
                StubRequirementSupport(
                    declaringProtocol: "EvidenceParameterizedDataSource",
                    name: "read(path:)",
                    kind: .method,
                    declarationIndex: 0,
                    runtimeEligibility: .compilerDescribed,
                    compiledEligibility: .generatedConformer
                )
            ]
        )
    )

    static func eraseToStubbedProtocol(_ conformer: Self) -> StubbedProtocol {
        conformer
    }

    func read(path: String) throws -> Data {
        try stub.throwingCall(path)
    }
}

private protocol EvidenceParameterizedSubscriptSource {
    subscript(section: Int, key: String) -> Data { get set }
}

private struct EvidenceParameterizedSubscriptSourceStubConformer:
    EvidenceParameterizedSubscriptSource, AutomaticStubConformer
{
    typealias StubbedProtocol = any EvidenceParameterizedSubscriptSource

    let stub: CompiledStub<Self>

    static let compilerEvidence = StubCompilerEvidence<StubbedProtocol>(
        runtimeConstruction: .requirements([
            .subscriptGetter(indexedBy: Int.self, String.self, returning: Data.self),
            .subscriptSetter(indexedBy: Int.self, String.self, assigning: Data.self)
        ]),
        compiledFallbackEligibility: .generatedConformer,
        sourceSupport: StubSourceSupportReport(
            protocolName: "EvidenceParameterizedSubscriptSource",
            requirements: []
        )
    )

    static func eraseToStubbedProtocol(_ conformer: Self) -> StubbedProtocol {
        conformer
    }

    subscript(section: Int, key: String) -> Data {
        get { stub.call(section, key) }
        set { stub.call(section, key, newValue) }
    }
}

private protocol EvidenceUnavailableSource {
    func value() -> Int
}

private struct EvidenceUnavailableSourceStubConformer:
    EvidenceUnavailableSource, AutomaticStubConformer
{
    typealias StubbedProtocol = any EvidenceUnavailableSource

    let stub: CompiledStub<Self>

    static let compilerEvidence = StubCompilerEvidence<StubbedProtocol>(
        runtimeConstruction: .unavailable(reason: "Compiler evidence requires compiled dispatch."),
        compiledFallbackEligibility: .generatedConformer,
        sourceSupport: StubSourceSupportReport(
            protocolName: "EvidenceUnavailableSource",
            requirements: []
        )
    )

    static func eraseToStubbedProtocol(_ conformer: Self) -> StubbedProtocol {
        conformer
    }

    func value() -> Int { stub.call() }
}

private protocol DefaultEvidenceSource {
    func value() -> Int
}

private struct DefaultEvidenceSourceStubConformer:
    DefaultEvidenceSource, AutomaticStubConformer
{
    typealias StubbedProtocol = any DefaultEvidenceSource

    let stub: CompiledStub<Self>

    static func eraseToStubbedProtocol(_ conformer: Self) -> StubbedProtocol {
        conformer
    }

    func value() -> Int { stub.call() }
}

@Suite struct CompilerEvidenceAutomaticRoutingTests {
    @Test func compilerDescribedParameterizedFoundationResultUsesRuntimeConstruction() throws {
        #expect(
            CompiledStub<EvidenceParameterizedDataSourceStubConformer>.compilerEvidence
                .sourceSupport.requirements.map(\.name) == ["read(path:)"]
        )

        let stub = CompiledStub<EvidenceParameterizedDataSourceStubConformer>.automatic()
        let expected = Data([2, 3, 5, 7])
        stub.when { try $0.read(path: "/test") }.thenReturn(expected)

        #expect(try stub().read(path: "/test") == expected)
        #expect(stub.constructionStrategy == .runtimeGenerated)
        #expect(stub.runtimeFallbackReason == nil)
    }

    @Test func unavailableRuntimeEvidenceSelectsCompiledFallback() {
        let stub = CompiledStub<EvidenceUnavailableSourceStubConformer>.automatic()
        stub.when { $0.value() }.thenReturn(42)

        #expect(stub().value() == 42)
        #expect(stub.constructionStrategy == .compiledFallback)
        #expect(
            stub.runtimeFallbackReason?.description.contains(
                "Compiler evidence requires compiled dispatch."
            ) == true
        )
    }

    @Test func compilerDescribedParameterizedSubscriptUsesRuntimeConstruction() {
        let stub = CompiledStub<EvidenceParameterizedSubscriptSourceStubConformer>.automatic()
        let expected = Data([11, 13, 17])
        stub.when { $0[2, "prime"] }.thenReturn(expected)

        #expect(stub()[2, "prime"] == expected)
        #expect(stub.constructionStrategy == .runtimeGenerated)
        #expect(stub.runtimeFallbackReason == nil)
    }

    @Test func existingAutomaticConformersRetainRuntimeDiscoveryDefault() {
        #expect(
            DefaultEvidenceSourceStubConformer.compilerEvidence.runtimeEligibility
                == .requiresRuntimeDiscovery
        )

        let stub = CompiledStub<DefaultEvidenceSourceStubConformer>.automatic()
        stub.when { $0.value() }.thenReturn(7)

        #expect(stub().value() == 7)
    }
}
