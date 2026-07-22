import Testing
@testable import TestDoubles

private struct DynamicFunctionABIPair: Sendable {
    let first: Int
    let second: Int
}

@Suite struct DynamicFunctionStackABITests {
    @Test func oneCompleteGPWordIsTheOnlyAcceptedSpill() {
        let x86NoSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 6),
            architecture: .x86_64
        )
        let armNoSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 8),
            architecture: .arm64
        )
        #expect(x86NoSpill?.usesStackArgument == false)
        #expect(armNoSpill?.usesStackArgument == false)

        let x86FirstSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 7),
            architecture: .x86_64
        )
        let armFirstSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 9),
            architecture: .arm64
        )
        #expect(x86FirstSpill?.usesStackArgument == true)
        #expect(armFirstSpill?.usesStackArgument == true)
        #expect(dynamicGenericArgumentLimit(architecture: .x86_64) == 7)
        #expect(dynamicGenericArgumentLimit(architecture: .arm64) == 9)

        #expect(
            dynamicFunctionArgumentPlan(
                Array(repeating: Int.self, count: 8),
                architecture: .x86_64
            ) == nil
        )
        #expect(
            dynamicFunctionArgumentPlan(
                Array(repeating: Int.self, count: 10),
                architecture: .arm64
            ) == nil
        )

        let x86AsyncResultSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 6),
            initialGeneralPurposeOffset: 1,
            architecture: .x86_64
        )
        let armAsyncResultSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 8),
            initialGeneralPurposeOffset: 1,
            architecture: .arm64
        )
        let x86TypedErrorSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 6),
            trailingGeneralPurposeWordCount: 1,
            architecture: .x86_64
        )
        let armTypedErrorSpill = dynamicFunctionArgumentPlan(
            Array(repeating: Int.self, count: 8),
            trailingGeneralPurposeWordCount: 1,
            architecture: .arm64
        )
        #expect(x86AsyncResultSpill?.usesStackArgument == true)
        #expect(armAsyncResultSpill?.usesStackArgument == true)
        #expect(x86TypedErrorSpill?.usesStackArgument == true)
        #expect(armTypedErrorSpill?.usesStackArgument == true)

        #expect(
            dynamicFunctionArgumentPlan(
                Array(repeating: Double.self, count: 9),
                architecture: .arm64
            ) == nil
        )
        #expect(
            dynamicFunctionArgumentPlan(
                Array(repeating: Int.self, count: 6) + [Int32.self],
                architecture: .x86_64
            ) == nil
        )
        #expect(
            dynamicFunctionArgumentPlan(
                Array(repeating: Int.self, count: 5)
                    + [DynamicFunctionABIPair.self],
                architecture: .x86_64
            ) == nil
        )
        #expect(
            dynamicFunctionArgumentPlan(
                Array(repeating: Int.self, count: 7)
                    + [DynamicFunctionABIPair.self],
                architecture: .arm64
            ) == nil
        )
    }

    @Test func asyncIncomingAdjustmentMatchesEachArchitecture() {
        #expect(
            dynamicAsyncStackAdjustmentByteCount(
                usesStackArgument: false,
                architecture: .x86_64
            ) == 0
        )
        #expect(
            dynamicAsyncStackAdjustmentByteCount(
                usesStackArgument: false,
                architecture: .arm64
            ) == 0
        )
        #expect(
            dynamicAsyncStackAdjustmentByteCount(
                usesStackArgument: true,
                architecture: .x86_64
            ) == 0
        )
        #expect(
            dynamicAsyncStackAdjustmentByteCount(
                usesStackArgument: true,
                architecture: .arm64
            ) == 16
        )
    }
}
