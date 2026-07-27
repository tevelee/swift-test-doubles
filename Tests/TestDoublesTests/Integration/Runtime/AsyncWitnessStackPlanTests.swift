import TestDoublesRuntime
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport
import Testing
@testable import TestDoubles

@Suite struct AsyncWitnessStackPlanTests {
    @Test func completeGeneralPurposeSpillsScaleAcrossArchitectures() {
        let cases:
            [(
                architecture: RuntimeArchitecture,
                argumentCount: Int,
                expected: AsyncWitnessStackPlan
            )] = [
                (.x86_64, 8, Self.plan(decoded: 16, adjustment: 32)),
                (.x86_64, 9, Self.plan(decoded: 24, adjustment: 32)),
                (.x86_64, 12, Self.plan(decoded: 48, adjustment: 64)),
                (.arm64, 10, Self.plan(decoded: 16, adjustment: 32)),
                (.arm64, 11, Self.plan(decoded: 24, adjustment: 48)),
                (.arm64, 14, Self.plan(decoded: 48, adjustment: 64))
            ]

        for testCase in cases {
            let method = MethodDescriptor(
                kind: .method,
                name: "load",
                index: 0,
                argumentTypes: Array(
                    repeating: Int.self,
                    count: testCase.argumentCount
                ),
                returnType: Int.self,
                isAsync: true
            )

            #expect(
                asyncWitnessStackPlan(
                    for: method,
                    architecture: testCase.architecture
                ) == testCase.expected
            )
        }
    }

    private static func plan(
        decoded: Int,
        adjustment: Int
    ) -> AsyncWitnessStackPlan {
        AsyncWitnessStackPlan(
            decodedStackByteCount: decoded,
            hiddenStackByteCount: 16,
            stackAdjustmentByteCount: adjustment
        )
    }
}
