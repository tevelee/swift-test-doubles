import EchoRuntimeReflection
import Testing
import TestDoublesResilientFixtures

@testable import TestDoublesRuntime

private enum FunctionBridgePlanError: Error {
    case failure
}

@Suite
struct FunctionBridgePlanTests {
    @Test
    func validatedPlansContainCompleteDirectionalTransport() throws {
        typealias Function = (Int, Double) -> String
        let function = try #require(FunctionTypeInfo(reflecting: Function.self))
        let analysis = FunctionBridgeAnalysis(function)

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
        let function = try #require(FunctionTypeInfo(reflecting: Function.self))
        let analysis = FunctionBridgeAnalysis(function)

        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(
            analysis.unsupportedReason(for: .directToGeneric)
                == "The dynamic bridge currently supports at most six parameters."
        )
    }

    @Test func resilientValuesNeverUseTheUncalibratedDynamicBridge() throws {
        typealias Function = (ResilientValueArgument) -> Int
        let function = try #require(FunctionTypeInfo(reflecting: Function.self))
        let analysis = FunctionBridgeAnalysis(function)

        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(analysis.validated(for: .genericToDirect) == nil)
        #expect(
            analysis.unsupportedReason(for: .directToGeneric)?.contains(
                "The dynamic closure bridge has no recording call"
            ) == true
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
        let function = try #require(FunctionTypeInfo(reflecting: Function.self))

        #if os(Linux) && arch(x86_64)
            let analysis = FunctionBridgeAnalysis(function)
            #expect(analysis.validated(for: .directToGeneric) == nil)
            #expect(analysis.validated(for: .genericToDirect) == nil)
            #expect(
                analysis.unsupportedReason(for: .directToGeneric)?.contains(
                    "Typed-throws closure values are unavailable on Linux x86_64"
                ) == true
            )
            return
        #endif

        let x86Analysis = FunctionBridgeAnalysis(
            function,
            architecture: .x86_64
        )
        #expect(x86Analysis.validated(for: .directToGeneric) != nil)
        #expect(x86Analysis.validated(for: .genericToDirect) == nil)
        #expect(
            x86Analysis.unsupportedReason(for: .genericToDirect)
                == "The x86_64 async typed-error return bridge cannot mix a full direct register bank with generic stack transport."
        )

        let armAnalysis = FunctionBridgeAnalysis(
            function,
            architecture: .arm64
        )
        #expect(armAnalysis.validated(for: .directToGeneric) != nil)
        #expect(armAnalysis.validated(for: .genericToDirect) != nil)
    }
}
