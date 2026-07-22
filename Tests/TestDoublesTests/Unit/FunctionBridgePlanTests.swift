import Echo
import Testing

@testable import TestDoubles

private enum FunctionBridgePlanError: Error {
    case failure
}

@Suite
struct FunctionBridgePlanTests {
    @Test
    func validatedPlansContainCompleteDirectionalTransport() throws {
        typealias Function = (Int, Double) -> String
        let metadata = try #require(reflect(Function.self) as? FunctionMetadata)
        let analysis = FunctionBridgeAnalysis(metadata)

        let argumentPlan = try #require(
            analysis.validated(for: .directToGeneric)
        )
        #expect(argumentPlan.direction == .directToGeneric)
        #expect(argumentPlan.parameterTypes.count == 2)
        #expect(argumentPlan.directArgumentLayouts.count == 2)

        let resultPlan = try #require(
            analysis.validated(for: .genericToDirect)
        )
        #expect(resultPlan.direction == .genericToDirect)
        #expect(resultPlan.parameterTypes.count == 2)
        #expect(resultPlan.directArgumentLayouts.count == 2)
    }

    @Test
    func unsupportedAnalysisCannotProduceAnExecutionPlan() throws {
        typealias Function = (
            Int,
            Int,
            Int,
            Int,
            Int,
            Int,
            Int
        ) -> Int
        let metadata = try #require(reflect(Function.self) as? FunctionMetadata)
        let analysis = FunctionBridgeAnalysis(metadata)

        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(
            analysis.unsupportedReason(for: .directToGeneric)
                == "The dynamic bridge currently supports at most six parameters."
        )
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test
    func x86AsyncTypedReturnRejectsTheUnsafeRegisterStackTransition() throws {
        typealias Function = (
            Int,
            Int,
            Int,
            Int,
            Int,
            Int
        ) async throws(FunctionBridgePlanError) -> Int
        let metadata = try #require(reflect(Function.self) as? FunctionMetadata)

        let x86Analysis = FunctionBridgeAnalysis(
            metadata,
            architecture: .x86_64
        )
        #expect(x86Analysis.validated(for: .directToGeneric) != nil)
        #expect(x86Analysis.validated(for: .genericToDirect) == nil)
        #expect(
            x86Analysis.unsupportedReason(for: .genericToDirect)
                == "The x86_64 async typed-error return bridge cannot mix a full direct register bank with generic stack transport."
        )

        let armAnalysis = FunctionBridgeAnalysis(
            metadata,
            architecture: .arm64
        )
        #expect(armAnalysis.validated(for: .directToGeneric) != nil)
        #expect(armAnalysis.validated(for: .genericToDirect) != nil)
    }
}
