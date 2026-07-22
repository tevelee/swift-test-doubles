import Echo
import Testing

@testable import TestDoubles

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
}
