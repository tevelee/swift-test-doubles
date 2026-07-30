import Testing
@testable import TestDoubles

#if arch(x86_64) || arch(arm64)

    struct AsyncMultiwordStackSpyForwardingTests {
        @Test func thirdVisibleSpillForwardsInDeclarationOrder() async throws {
            let spy = try Spy<any ThirdSpilledAsyncForwardingProbe>(
                forwardingTo: RealThirdSpilledAsyncForwardingProbe()
            )

            #expect(
                await forwardedThird(spy())
                    == foldedAsyncForwardingWords([
                        0x3132_3334, 0x4142_4344, 0x5152_5354
                    ])
            )
        }

        @Test func fourthVisibleSpillForwardsImmediately() async throws {
            let spy = try Spy<any FourthSpilledAsyncForwardingProbe>(
                forwardingTo: RealFourthSpilledAsyncForwardingProbe()
            )

            #expect(
                await forwardedFourthImmediate(spy())
                    == foldedAsyncForwardingWords([
                        0x1112_1314, 0x2122_2324,
                        0x3132_3334, 0x4142_4344
                    ])
            )
        }

        @Test func fourthVisibleSpillSurvivesGenuineSuspension() async throws {
            let spy = try Spy<any FourthSpilledAsyncForwardingProbe>(
                forwardingTo: RealFourthSpilledAsyncForwardingProbe()
            )

            #expect(
                await forwardedFourthSuspending(spy())
                    == foldedAsyncForwardingWords([
                        0x5152_5354, 0x6162_6364,
                        0x7172_7374, 0x0102_0304
                    ])
            )
        }

        @Test func fourthVisibleSpillPreservesUntypedErrorTransport() async throws {
            let spy = try Spy<any FourthSpilledAsyncForwardingProbe>(
                forwardingTo: RealFourthSpilledAsyncForwardingProbe()
            )
            let error = await #expect(throws: AsyncStackUntypedError.self) {
                _ = try await forwardedFourthThrowing(spy())
            }

            #expect(
                error
                    == .failed(
                        foldedAsyncForwardingWords([
                            0x1516_1718, 0x2526_2728,
                            0x3536_3738, 0x4546_4748
                        ])
                    )
            )
        }

        @Test func fourthVisibleSpillPreservesIndirectResultStorage() async throws {
            let spy = try Spy<any FourthSpilledAsyncForwardingProbe>(
                forwardingTo: RealFourthSpilledAsyncForwardingProbe()
            )

            #expect(
                await forwardedFourthIndirect(spy())
                    == AsyncForwardingIndirectResult(
                        first: 0x191a_1b1c,
                        second: 0x292a_2b2c,
                        checksum: foldedAsyncForwardingWords([
                            0x191a_1b1c, 0x292a_2b2c,
                            0x393a_3b3c, 0x494a_4b4c
                        ]),
                        marker: 0x494a_4b4c,
                        count: 4
                    )
            )
        }

        @Test func eighthVisibleSpillForwardsInDeclarationOrder() async throws {
            let spy = try Spy<any EighthSpilledAsyncForwardingProbe>(
                forwardingTo: RealEighthSpilledAsyncForwardingProbe()
            )
            let service: any EighthSpilledAsyncForwardingProbe = spy()
            let expected = foldedAsyncForwardingWords([
                0x1112_1314, 0x2122_2324,
                0x3132_3334, 0x4142_4344,
                0x5152_5354, 0x6162_6364,
                0x7172_7374, 0x0102_0304
            ])

            #if arch(x86_64)
                #expect(
                    await service.call(
                        1, 2, 3, 4, 5, 6,
                        0x1112_1314, 0x2122_2324,
                        0x3132_3334, 0x4142_4344,
                        0x5152_5354, 0x6162_6364,
                        0x7172_7374, 0x0102_0304
                    ) == expected
                )
            #else
                #expect(
                    await service.call(
                        1, 2, 3, 4, 5, 6, 7, 8,
                        0x1112_1314, 0x2122_2324,
                        0x3132_3334, 0x4142_4344,
                        0x5152_5354, 0x6162_6364,
                        0x7172_7374, 0x0102_0304
                    ) == expected
                )
            #endif
        }

        @Test func floatingPointSpillRemainsFailClosed() {
            expectUnsupportedProtocolShape(containing: "floating-point") {
                _ = try Spy<any FloatingPointSpilledAsyncForwardingProbe>(
                    forwardingTo: RealFloatingPointSpilledAsyncForwardingProbe()
                )
            }
        }

        @Test func associatedDependentSpillRemainsFailClosed() {
            expectUnsupportedProtocolShape(containing: "dependent") {
                _ = try Spy<any DependentSpilledAsyncForwardingProbe<Int>>(
                    forwardingTo: RealDependentSpilledAsyncForwardingProbe()
                )
            }
        }
    }

#endif
