import EchoRuntimeReflection
import Foundation
import InternalRuntimeContract
import Testing
import TestDoublesResilientFixtures

@testable import TestDoublesRuntime

@Suite struct CompilerResultTransportFunctionBridgeTests {
    @Test func throwingDataEvidenceEnablesBothBridgeDirections() throws {
        typealias Closure = @Sendable (String) throws -> Data
        let function = try #require(FunctionTypeInfo(reflecting: Closure.self))
        let catalog = evidenceCatalog(
            returning: Data.self,
            transport: .direct,
            isThrowing: true,
            isAsync: false
        )
        let analysis = FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: catalog
        )

        let argument = try #require(analysis.validated(for: .directToGeneric))
        let result = try #require(analysis.validated(for: .genericToDirect))

        #expect(argument.resultLayout != .indirect)
        #expect(result.resultLayout != .indirect)
    }

    #if compiler(>=6.4)
        @Test func asyncUUIDEvidencePreservesIndirectResultTransport() throws {
            typealias Closure = @Sendable (Int) async -> UUID
            let function = try #require(FunctionTypeInfo(reflecting: Closure.self))
            let catalog = evidenceCatalog(
                returning: UUID.self,
                transport: .indirect,
                isThrowing: false,
                isAsync: true
            )
            let analysis = FunctionBridgeAnalysis(
                function,
                resultTransportEvidenceCatalog: catalog
            )

            let argument = try #require(analysis.validated(for: .directToGeneric))
            let result = try #require(analysis.validated(for: .genericToDirect))

            #expect(argument.resultLayout == .indirect)
            #expect(result.resultLayout == .indirect)
        }
    #endif

    @Test func evidenceMustMatchTheClosureEffectsExactly() throws {
        typealias Closure = @Sendable (String) async throws -> Data
        let function = try #require(FunctionTypeInfo(reflecting: Closure.self))
        let synchronousCatalog = evidenceCatalog(
            returning: Data.self,
            transport: .direct,
            isThrowing: true,
            isAsync: false
        )
        let analysis = FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: synchronousCatalog
        )

        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(analysis.validated(for: .genericToDirect) == nil)
    }

    @Test func evidenceDoesNotAuthorizeAnUncertainClosureParameter() throws {
        typealias Closure = @Sendable (Data) -> Int
        let function = try #require(FunctionTypeInfo(reflecting: Closure.self))
        let catalog = evidenceCatalog(
            returning: Data.self,
            transport: .direct,
            isThrowing: false,
            isAsync: false
        )
        let analysis = FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: catalog
        )

        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(analysis.validated(for: .genericToDirect) == nil)
    }

    @Test func evidenceDoesNotAuthorizeACustomResilientResult() throws {
        typealias Closure = @Sendable (String) -> ResilientValueArgument
        let function = try #require(FunctionTypeInfo(reflecting: Closure.self))
        let catalog = evidenceCatalog(
            returning: Data.self,
            transport: .direct,
            isThrowing: false,
            isAsync: false
        )
        let analysis = FunctionBridgeAnalysis(
            function,
            resultTransportEvidenceCatalog: catalog
        )

        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(analysis.validated(for: .genericToDirect) == nil)
    }

    private func evidenceCatalog<Result>(
        returning resultType: Result.Type,
        transport: RuntimeAutomaticRequirementAdapter.ResultTransport,
        isThrowing: Bool,
        isAsync: Bool
    ) -> CompilerResultTransportEvidenceCatalog {
        CompilerResultTransportEvidenceCatalog([
            RuntimeAutomaticRequirementAdapter(
                kind: .method,
                resultType: resultType,
                resultTransport: transport,
                isThrowing: isThrowing,
                isAsync: isAsync
            )
        ])
    }
}
