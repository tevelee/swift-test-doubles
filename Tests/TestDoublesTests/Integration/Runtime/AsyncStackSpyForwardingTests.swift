import Testing
@testable import TestDoubles

struct AsyncForwardingWideValue: Sendable {
    let first: Int
    let second: Int
}

struct AsyncForwardingPaddedValue: Sendable {
    let word: UInt64
    let byte: UInt8
}

struct AsyncForwardingIndirectResult: Equatable, Sendable {
    let first: Int
    let second: Int
    let checksum: Int
    let marker: Int
    let count: Int
}

func foldedAsyncForwardingWords(_ words: [Int]) -> Int {
    words.reduce(0x1020_3040) { partial, word in
        (partial &* 31) &+ word
    }
}

// This whole suite exercises the forwarding trampoline's per-architecture
// register/stack spill layout with hardcoded 64-bit patterns, so it has no
// meaning without that trampoline (wasm32 and any future architecture we
// haven't proven the spill layout for) and is skipped there entirely.
#if arch(x86_64) || arch(arm64)

    #if arch(x86_64)
        protocol FirstSpilledAsyncForwardingProbe: Sendable {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) async -> Int
            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) async -> Int
        }

        protocol ThrowingSpilledAsyncForwardingProbe: Sendable {
            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) async throws -> Int
        }

        struct RealFirstSpilledAsyncForwardingProbe:
            FirstSpilledAsyncForwardingProbe
        {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) async -> Int { a6 }

            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) async -> Int {
                await Task.yield()
                return a6
            }
        }

        struct RealThrowingSpilledAsyncForwardingProbe:
            ThrowingSpilledAsyncForwardingProbe
        {
            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) async throws -> Int {
                throw AsyncStackUntypedError.failed(a6)
            }
        }

        protocol SecondSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
            ) async -> Int
        }

        struct RealSecondSpilledAsyncForwardingProbe:
            SecondSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
            ) async -> Int {
                foldedAsyncForwardingWords([a6, a7])
            }
        }

        protocol ThirdSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> Int
        }

        struct RealThirdSpilledAsyncForwardingProbe:
            ThirdSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> Int {
                foldedAsyncForwardingWords([a6, a7, a8])
            }
        }

        protocol FourthSpilledAsyncForwardingProbe: Sendable {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async -> Int
            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async -> Int
            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async throws -> Int
            func indirect(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> AsyncForwardingIndirectResult
        }

        struct RealFourthSpilledAsyncForwardingProbe:
            FourthSpilledAsyncForwardingProbe
        {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async -> Int {
                foldedAsyncForwardingWords([a6, a7, a8, a9])
            }

            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async -> Int {
                await Task.yield()
                return foldedAsyncForwardingWords([a6, a7, a8, a9])
            }

            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async throws -> Int {
                throw AsyncStackUntypedError.failed(
                    foldedAsyncForwardingWords([a6, a7, a8, a9])
                )
            }

            func indirect(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> AsyncForwardingIndirectResult {
                AsyncForwardingIndirectResult(
                    first: a5,
                    second: a6,
                    checksum: foldedAsyncForwardingWords([a5, a6, a7, a8]),
                    marker: a8,
                    count: 4
                )
            }
        }

        protocol FifthSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int
            ) async -> Int
        }

        struct RealFifthSpilledAsyncForwardingProbe:
            FifthSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int
            ) async -> Int { a10 }
        }

        protocol FloatingPointSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Double, _ a1: Double, _ a2: Double,
                _ a3: Double, _ a4: Double, _ a5: Double,
                _ a6: Double, _ a7: Double, _ a8: Double
            ) async -> Double
        }

        struct RealFloatingPointSpilledAsyncForwardingProbe:
            FloatingPointSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Double, _ a1: Double, _ a2: Double,
                _ a3: Double, _ a4: Double, _ a5: Double,
                _ a6: Double, _ a7: Double, _ a8: Double
            ) async -> Double { a8 }
        }

        protocol DependentSpilledAsyncForwardingProbe<Value>: Sendable {
            associatedtype Value: Sendable
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int,
                _ a3: Int, _ a4: Int, _ a5: Int,
                _ value: Value
            ) async -> Int
        }

        struct RealDependentSpilledAsyncForwardingProbe:
            DependentSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int,
                _ a3: Int, _ a4: Int, _ a5: Int,
                _ value: Int
            ) async -> Int { value }
        }

        protocol WideSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ value: AsyncForwardingWideValue
            ) async -> Int
        }

        struct RealWideSpilledAsyncForwardingProbe:
            WideSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ value: AsyncForwardingWideValue
            ) async -> Int { value.second }
        }

        protocol PaddedSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ value: AsyncForwardingPaddedValue
            ) async -> Int
        }

        struct RealPaddedSpilledAsyncForwardingProbe:
            PaddedSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ value: AsyncForwardingPaddedValue
            ) async -> Int { Int(value.byte) }
        }

        protocol TypedErrorSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int,
                _ a3: Int, _ a4: Int, _ a5: Int
            ) async throws(AsyncStackLargeError) -> Int
        }

        struct RealTypedErrorSpilledAsyncForwardingProbe:
            TypedErrorSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int,
                _ a3: Int, _ a4: Int, _ a5: Int
            ) async throws(AsyncStackLargeError) -> Int { a5 }
        }

        protocol AccessorSpilledAsyncForwardingProbe: Sendable {
            subscript(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) -> Int { get async }
        }

        struct RealAccessorSpilledAsyncForwardingProbe:
            AccessorSpilledAsyncForwardingProbe
        {
            subscript(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int
            ) -> Int {
                get async { a6 }
            }
        }

        private func forwardedImmediate(
            _ probe: any FirstSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.immediate(1, 2, 3, 4, 5, 6, 0x7172_7374_7576_7778)
        }

        private func forwardedSuspending(
            _ probe: any FirstSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.suspending(1, 2, 3, 4, 5, 6, 0x6162_6364_6566_6768)
        }

        func forwardedThird(
            _ probe: any ThirdSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.call(
                1, 2, 3, 4, 5, 6,
                0x3132_3334, 0x4142_4344, 0x5152_5354
            )
        }

        func forwardedFourthImmediate(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.immediate(
                1, 2, 3, 4, 5, 6,
                0x1112_1314, 0x2122_2324,
                0x3132_3334, 0x4142_4344
            )
        }

        func forwardedFourthSuspending(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.suspending(
                1, 2, 3, 4, 5, 6,
                0x5152_5354, 0x6162_6364,
                0x7172_7374, 0x0102_0304
            )
        }

        func forwardedFourthThrowing(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async throws -> Int {
            try await probe.throwing(
                1, 2, 3, 4, 5, 6,
                0x1516_1718, 0x2526_2728,
                0x3536_3738, 0x4546_4748
            )
        }

        func forwardedFourthIndirect(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async -> AsyncForwardingIndirectResult {
            await probe.indirect(
                1, 2, 3, 4, 5,
                0x191a_1b1c, 0x292a_2b2c,
                0x393a_3b3c, 0x494a_4b4c
            )
        }

    #else
        protocol FirstSpilledAsyncForwardingProbe: Sendable {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> Int
            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> Int
        }

        protocol ThrowingSpilledAsyncForwardingProbe: Sendable {
            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async throws -> Int
        }

        struct RealFirstSpilledAsyncForwardingProbe:
            FirstSpilledAsyncForwardingProbe
        {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> Int { a8 }

            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async -> Int {
                await Task.yield()
                return a8
            }
        }

        struct RealThrowingSpilledAsyncForwardingProbe:
            ThrowingSpilledAsyncForwardingProbe
        {
            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) async throws -> Int {
                throw AsyncStackUntypedError.failed(a8)
            }
        }

        protocol SecondSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async -> Int
        }

        struct RealSecondSpilledAsyncForwardingProbe:
            SecondSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
            ) async -> Int {
                foldedAsyncForwardingWords([a8, a9])
            }
        }

        protocol ThirdSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int
            ) async -> Int
        }

        struct RealThirdSpilledAsyncForwardingProbe:
            ThirdSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int
            ) async -> Int {
                foldedAsyncForwardingWords([a8, a9, a10])
            }
        }

        protocol FourthSpilledAsyncForwardingProbe: Sendable {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
            ) async -> Int
            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
            ) async -> Int
            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
            ) async throws -> Int
            func indirect(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int
            ) async -> AsyncForwardingIndirectResult
        }

        struct RealFourthSpilledAsyncForwardingProbe:
            FourthSpilledAsyncForwardingProbe
        {
            func immediate(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
            ) async -> Int {
                foldedAsyncForwardingWords([a8, a9, a10, a11])
            }

            func suspending(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
            ) async -> Int {
                await Task.yield()
                return foldedAsyncForwardingWords([a8, a9, a10, a11])
            }

            func throwing(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int
            ) async throws -> Int {
                throw AsyncStackUntypedError.failed(
                    foldedAsyncForwardingWords([a8, a9, a10, a11])
                )
            }

            func indirect(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int
            ) async -> AsyncForwardingIndirectResult {
                AsyncForwardingIndirectResult(
                    first: a7,
                    second: a8,
                    checksum: foldedAsyncForwardingWords([a7, a8, a9, a10]),
                    marker: a10,
                    count: 4
                )
            }
        }

        protocol FifthSpilledAsyncForwardingProbe: Sendable {
            // This must overflow the supported four-word forwarding window.
            // swiftlint:disable:next function_parameter_count
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int,
                _ a12: Int
            ) async -> Int
        }

        struct RealFifthSpilledAsyncForwardingProbe:
            FifthSpilledAsyncForwardingProbe
        {
            // swiftlint:disable:next function_parameter_count
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ a8: Int, _ a9: Int, _ a10: Int, _ a11: Int,
                _ a12: Int
            ) async -> Int { a12 }
        }

        protocol FloatingPointSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Double, _ a1: Double, _ a2: Double,
                _ a3: Double, _ a4: Double, _ a5: Double,
                _ a6: Double, _ a7: Double, _ a8: Double
            ) async -> Double
        }

        struct RealFloatingPointSpilledAsyncForwardingProbe:
            FloatingPointSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Double, _ a1: Double, _ a2: Double,
                _ a3: Double, _ a4: Double, _ a5: Double,
                _ a6: Double, _ a7: Double, _ a8: Double
            ) async -> Double { a8 }
        }

        protocol DependentSpilledAsyncForwardingProbe<Value>: Sendable {
            associatedtype Value: Sendable
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ value: Value
            ) async -> Int
        }

        struct RealDependentSpilledAsyncForwardingProbe:
            DependentSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
                _ value: Int
            ) async -> Int { value }
        }

        protocol WideSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int,
                _ value: AsyncForwardingWideValue
            ) async -> Int
        }

        struct RealWideSpilledAsyncForwardingProbe:
            WideSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int,
                _ value: AsyncForwardingWideValue
            ) async -> Int { value.second }
        }

        protocol PaddedSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int,
                _ value: AsyncForwardingPaddedValue
            ) async -> Int
        }

        struct RealPaddedSpilledAsyncForwardingProbe:
            PaddedSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int,
                _ value: AsyncForwardingPaddedValue
            ) async -> Int { Int(value.byte) }
        }

        protocol TypedErrorSpilledAsyncForwardingProbe: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
            ) async throws(AsyncStackLargeError) -> Int
        }

        struct RealTypedErrorSpilledAsyncForwardingProbe:
            TypedErrorSpilledAsyncForwardingProbe
        {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
                _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int
            ) async throws(AsyncStackLargeError) -> Int { a7 }
        }

        protocol AccessorSpilledAsyncForwardingProbe: Sendable {
            subscript(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) -> Int { get async }
        }

        struct RealAccessorSpilledAsyncForwardingProbe:
            AccessorSpilledAsyncForwardingProbe
        {
            subscript(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
                _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
            ) -> Int {
                get async { a8 }
            }
        }

        private func forwardedImmediate(
            _ probe: any FirstSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.immediate(
                1, 2, 3, 4, 5, 6, 7, 8, 0x7172_7374_7576_7778
            )
        }

        private func forwardedSuspending(
            _ probe: any FirstSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.suspending(
                1, 2, 3, 4, 5, 6, 7, 8, 0x6162_6364_6566_6768
            )
        }

        func forwardedThird(
            _ probe: any ThirdSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.call(
                1, 2, 3, 4, 5, 6, 7, 8,
                0x3132_3334, 0x4142_4344, 0x5152_5354
            )
        }

        func forwardedFourthImmediate(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.immediate(
                1, 2, 3, 4, 5, 6, 7, 8,
                0x1112_1314, 0x2122_2324,
                0x3132_3334, 0x4142_4344
            )
        }

        func forwardedFourthSuspending(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async -> Int {
            await probe.suspending(
                1, 2, 3, 4, 5, 6, 7, 8,
                0x5152_5354, 0x6162_6364,
                0x7172_7374, 0x0102_0304
            )
        }

        func forwardedFourthThrowing(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async throws -> Int {
            try await probe.throwing(
                1, 2, 3, 4, 5, 6, 7, 8,
                0x1516_1718, 0x2526_2728,
                0x3536_3738, 0x4546_4748
            )
        }

        func forwardedFourthIndirect(
            _ probe: any FourthSpilledAsyncForwardingProbe
        ) async -> AsyncForwardingIndirectResult {
            await probe.indirect(
                1, 2, 3, 4, 5, 6, 7,
                0x191a_1b1c, 0x292a_2b2c,
                0x393a_3b3c, 0x494a_4b4c
            )
        }

    #endif

    struct AsyncStackSpyForwardingTests {
        @Test func immediateTargetReceivesCopiedVisibleSpill() async throws {
            let target: any FirstSpilledAsyncForwardingProbe =
                RealFirstSpilledAsyncForwardingProbe()
            let spy = try Spy<any FirstSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )

            #expect(
                await forwardedImmediate(spy()) == 0x7172_7374_7576_7778
            )
        }

        @Test func suspendedTargetRestoresTheCallerStackOnce() async throws {
            let target: any FirstSpilledAsyncForwardingProbe =
                RealFirstSpilledAsyncForwardingProbe()
            let spy = try Spy<any FirstSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )

            #expect(
                await forwardedSuspending(spy()) == 0x6162_6364_6566_6768
            )
        }

        @Test func untypedThrowingVisibleSpillNowForwards() async throws {
            let target: any ThrowingSpilledAsyncForwardingProbe =
                RealThrowingSpilledAsyncForwardingProbe()
            let spy = try Spy<any ThrowingSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
            let service: any ThrowingSpilledAsyncForwardingProbe = spy()

            let error = await #expect(throws: AsyncStackUntypedError.self) {
                #if arch(x86_64)
                    _ = try await service.throwing(1, 2, 3, 4, 5, 6, 7)
                #else
                    _ = try await service.throwing(1, 2, 3, 4, 5, 6, 7, 8, 9)
                #endif
            }
            #if arch(x86_64)
                #expect(error == .failed(7))
            #else
                #expect(error == .failed(9))
            #endif
        }

        @Test func secondVisibleSpillForwardsInDeclarationOrder() async throws {
            let target: any SecondSpilledAsyncForwardingProbe =
                RealSecondSpilledAsyncForwardingProbe()
            let spy = try Spy<any SecondSpilledAsyncForwardingProbe>(
                forwardingTo: target
            )
            let service: any SecondSpilledAsyncForwardingProbe = spy()

            #if arch(x86_64)
                #expect(
                    await service.call(1, 2, 3, 4, 5, 6, 7, 8)
                        == foldedAsyncForwardingWords([7, 8])
                )
            #else
                #expect(
                    await service.call(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
                        == foldedAsyncForwardingWords([9, 10])
                )
            #endif
        }

        @Test func splitWideSpillRemainsFailClosed() {
            let target: any WideSpilledAsyncForwardingProbe =
                RealWideSpilledAsyncForwardingProbe()
            #expect(throws: StubError.self) {
                _ = try Spy<any WideSpilledAsyncForwardingProbe>(
                    forwardingTo: target
                )
            }
        }

        @Test func paddedSpillRemainsFailClosed() {
            let target: any PaddedSpilledAsyncForwardingProbe =
                RealPaddedSpilledAsyncForwardingProbe()
            #expect(throws: StubError.self) {
                _ = try Spy<any PaddedSpilledAsyncForwardingProbe>(
                    forwardingTo: target
                )
            }
        }

        @Test func typedErrorDestinationSpillRemainsFailClosed() {
            let target: any TypedErrorSpilledAsyncForwardingProbe =
                RealTypedErrorSpilledAsyncForwardingProbe()
            #expect(throws: StubError.self) {
                _ = try Spy<any TypedErrorSpilledAsyncForwardingProbe>(
                    forwardingTo: target
                )
            }
        }

        @Test func asyncAccessorSpillRemainsFailClosed() {
            let target: any AccessorSpilledAsyncForwardingProbe =
                RealAccessorSpilledAsyncForwardingProbe()
            #expect(throws: StubError.self) {
                _ = try Spy<any AccessorSpilledAsyncForwardingProbe>(
                    forwardingTo: target
                )
            }
        }
    }

#endif
