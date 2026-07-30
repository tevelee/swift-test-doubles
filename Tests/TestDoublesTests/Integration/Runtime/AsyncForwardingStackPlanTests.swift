import TestDoublesRuntime
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport
import Testing
@testable import TestDoubles

struct AsyncForwardingStackPlanTests {
    @Test func allowsOneThroughEightCompleteVisibleWordsOnBothArchitectures() {
        let cases: [(RuntimeArchitecture, Int, [Int])] = [
            (.x86_64, 6, [16, 32, 32, 48, 48, 64, 64, 80]),
            (.arm64, 8, [32, 32, 48, 48, 64, 64, 80, 80])
        ]

        for (architecture, registerCount, stackByteCounts) in cases {
            for visibleWordCount in 1 ... 8 {
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

    @Test func ninthVisibleWordAndTypedErrorRemainFailClosed() {
        #expect(
            asyncForwardingStackPlan(
                for: method(argumentCount: 15),
                architecture: .x86_64
            ) == nil
        )
        #expect(
            asyncForwardingStackPlan(
                for: method(argumentCount: 17),
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

    @Test func splitsSIMDSpillsIntoVisibleWordsUpToTheEightWordLimit() {
        let method = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + Array(repeating: SIMD4<Float>.self, count: 11),
            returnType: UInt64.self,
            isAsync: true
        )

        #expect(
            asyncForwardingStackPlan(
                for: method,
                architecture: .arm64
            )
                == AsyncForwardingStackPlan(
                    visibleArgumentLocations: [
                        .init(
                            storage: .stack(byteOffset: 0),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 8),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 16),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 24),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 32),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 40),
                            valueOffset: 0,
                            byteCount: 8
                        )
                    ],
                    outgoingStackByteCount: 64,
                    completionStackAdjustmentByteCount: 0
                )
        )
        #expect(
            asyncForwardingStackPlan(
                for: method,
                architecture: .x86_64
            )
                == AsyncForwardingStackPlan(
                    visibleArgumentLocations: [
                        .init(
                            storage: .stack(byteOffset: 0),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 8),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 16),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 24),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 32),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 40),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 48),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(byteOffset: 56),
                            valueOffset: 0,
                            byteCount: 8
                        )
                    ],
                    outgoingStackByteCount: 80,
                    completionStackAdjustmentByteCount: 0
                )
        )
    }

    @Test func acceptsOneNarrowIntegerAsACompleteStackWord() {
        let method = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + [UInt32.self],
            returnType: UInt64.self,
            isAsync: true
        )

        for architecture in [
            RuntimeArchitecture.arm64,
            RuntimeArchitecture.x86_64
        ] {
            let plan = asyncForwardingStackPlan(
                for: method,
                architecture: architecture
            )
            #expect(plan != nil)
            #expect(
                plan?.visibleArgumentLocations.last
                    == CallFrameArgumentLocation(
                        storage: .stack(
                            byteOffset: architecture == .arm64 ? 0 : 16
                        ),
                        valueOffset: 0,
                        byteCount: 8
                    )
            )
        }
    }

    @Test func acceptsRepeatedNarrowIntegersInPackedStackWords() {
        let method = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + [UInt32.self, UInt16.self],
            returnType: UInt64.self,
            isAsync: true
        )

        #expect(
            asyncForwardingStackPlan(
                for: method,
                architecture: .arm64
            )?.visibleArgumentLocations.count == 1
        )
        #expect(
            asyncForwardingStackPlan(
                for: method,
                architecture: .x86_64
            )?.visibleArgumentLocations.count == 4
        )
    }

    @Test func acceptsACompleteTwoWordIntegerValueButRejectsASplitOne() {
        let completeMethod = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + [AsyncTwoWordSpillValue.self],
            returnType: UInt64.self,
            isAsync: true
        )

        #expect(
            asyncForwardingStackPlan(
                for: completeMethod,
                architecture: .arm64
            )?.visibleArgumentLocations
                == [
                    .init(
                        storage: .stack(byteOffset: 0),
                        valueOffset: 0,
                        byteCount: 8
                    ),
                    .init(
                        storage: .stack(byteOffset: 8),
                        valueOffset: 0,
                        byteCount: 8
                    )
                ]
        )
        #expect(
            asyncForwardingStackPlan(
                for: completeMethod,
                architecture: .x86_64
            )?.visibleArgumentLocations
                == [
                    .init(
                        storage: .stack(byteOffset: 0),
                        valueOffset: 0,
                        byteCount: 8
                    ),
                    .init(
                        storage: .stack(byteOffset: 8),
                        valueOffset: 0,
                        byteCount: 8
                    ),
                    .init(
                        storage: .stack(byteOffset: 16),
                        valueOffset: 0,
                        byteCount: 8
                    ),
                    .init(
                        storage: .stack(byteOffset: 24),
                        valueOffset: 0,
                        byteCount: 8
                    )
                ]
        )

        let splitMethod = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 7)
                + [AsyncTwoWordSpillValue.self],
            returnType: UInt64.self,
            isAsync: true
        )
        #expect(
            asyncForwardingStackPlan(
                for: splitMethod,
                architecture: .arm64
            ) == nil
        )
    }

    @Test func acceptsACompletePaddedTwoWordValue() {
        let method = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + [AsyncPaddedTwoWordSpillValue.self],
            returnType: UInt64.self,
            isAsync: true
        )

        for architecture in [
            RuntimeArchitecture.arm64,
            RuntimeArchitecture.x86_64
        ] {
            let plan = asyncForwardingStackPlan(
                for: method,
                architecture: architecture
            )
            #expect(plan != nil)
            #expect(
                plan?.visibleArgumentLocations.suffix(2)
                    == [
                        .init(
                            storage: .stack(
                                byteOffset:
                                    architecture == .arm64 ? 0 : 16
                            ),
                            valueOffset: 0,
                            byteCount: 8
                        ),
                        .init(
                            storage: .stack(
                                byteOffset:
                                    architecture == .arm64 ? 8 : 24
                            ),
                            valueOffset: 0,
                            byteCount: 8
                        )
                    ]
            )
        }
    }

    @Test func acceptsAnIndependentIndirectPointerAsOneStackWord() {
        let method = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + [AsyncIndirectSpillValue.self],
            returnType: UInt64.self,
            isAsync: true
        )

        for architecture in [
            RuntimeArchitecture.arm64,
            RuntimeArchitecture.x86_64
        ] {
            let plan = asyncForwardingStackPlan(
                for: method,
                architecture: architecture
            )
            #expect(plan != nil)
            #expect(
                plan?.visibleArgumentLocations.last
                    == .init(
                        storage: .stack(
                            byteOffset: architecture == .arm64 ? 0 : 16
                        ),
                        valueOffset: 0,
                        byteCount: 8
                    )
            )
        }
    }

    @Test func acceptsFourRegisterSIMDSpillsButRejectsASplitValue() {
        let cases: [(RuntimeArchitecture, Int)] = [
            (.arm64, 8),
            (.x86_64, 6)
        ]
        for (architecture, integerCount) in cases {
            let method = MethodDescriptor(
                kind: .method,
                name: "inspect",
                index: 0,
                argumentTypes:
                    Array(repeating: Int.self, count: integerCount)
                    + Array(repeating: SIMD16<Float>.self, count: 3),
                returnType: UInt64.self,
                isAsync: true
            )
            let plan = asyncForwardingStackPlan(
                for: method,
                architecture: architecture
            )
            #expect(plan?.visibleArgumentLocations.count == 8)
            #expect(plan?.outgoingStackByteCount == 80)
        }

        let splitMethod = MethodDescriptor(
            kind: .method,
            name: "inspect",
            index: 0,
            argumentTypes:
                Array(repeating: Int.self, count: 8)
                + Array(repeating: SIMD4<Float>.self, count: 7)
                + [SIMD8<Float>.self],
            returnType: UInt64.self,
            isAsync: true
        )
        #expect(
            asyncForwardingStackPlan(
                for: splitMethod,
                architecture: .arm64
            ) == nil
        )
        #expect(
            asyncForwardingStackPlan(
                for: splitMethod,
                architecture: .x86_64
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
