import TestDoublesRuntime
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport
import Testing
@testable import TestDoubles

struct AsyncForwardingStackPlanTests {
    @Test func allowsOneThroughFourCompleteVisibleWordsOnBothArchitectures() {
        let cases: [(RuntimeArchitecture, Int, [Int])] = [
            (.x86_64, 6, [16, 32, 32, 48]),
            (.arm64, 8, [32, 32, 48, 48])
        ]

        for (architecture, registerCount, stackByteCounts) in cases {
            for visibleWordCount in 1 ... 4 {
                let expectedLocations = (0 ..< visibleWordCount).map {
                    CallFrameArgumentLocation(
                        storage: .stack(byteOffset: $0 * 8),
                        valueOffset: 0,
                        byteCount: 8
                    )
                }
                #expect(
                    asyncForwardingStackPlan(
                        for: method(
                            argumentCount: registerCount + visibleWordCount
                        ),
                        architecture: architecture
                    )
                        == AsyncForwardingStackPlan(
                            visibleArgumentLocations: expectedLocations,
                            outgoingStackByteCount:
                                stackByteCounts[visibleWordCount - 1],
                            completionStackAdjustmentByteCount: 0
                        )
                )
            }
        }
    }

    @Test func fifthVisibleWordAndTypedErrorRemainFailClosed() {
        #expect(
            asyncForwardingStackPlan(
                for: method(argumentCount: 11),
                architecture: .x86_64
            ) == nil
        )
        #expect(
            asyncForwardingStackPlan(
                for: method(argumentCount: 13),
                architecture: .arm64
            ) == nil
        )
        #expect(
            asyncForwardingStackPlan(
                for: method(
                    argumentCount: 6,
                    typedError: AsyncStackLargeError.self
                ),
                architecture: .x86_64
            ) == nil
        )
        #expect(
            asyncForwardingStackPlan(
                for: method(
                    argumentCount: 8,
                    typedError: AsyncStackLargeError.self
                ),
                architecture: .arm64
            ) == nil
        )
    }

    private func method(
        argumentCount: Int,
        typedError: (any Error.Type)? = nil
    ) -> MethodDescriptor {
        MethodDescriptor(
            kind: .method,
            name: "load",
            index: 0,
            argumentTypes: Array(repeating: Int.self, count: argumentCount),
            returnType: Int.self,
            typedErrorType: typedError,
            isThrowing: typedError != nil,
            isAsync: true
        )
    }
}
