import Testing
import TestDoubles

/// End-to-end coverage for multi-register SIMD (an 8-wide audio batch).
protocol AudioGainProcessor {
    func applyGain(_ samples: SIMD8<Float>, gain: Float) -> SIMD8<Float>
}

private struct RealAudioGainProcessor: AudioGainProcessor {
    func applyGain(_ samples: SIMD8<Float>, gain: Float) -> SIMD8<Float> {
        samples * gain
    }
}

@Suite struct MultiRegisterSIMDTests {
    @Test func stubbedProcessorReturnsAConfiguredBatch() throws {
        let input = SIMD8<Float>(1, 2, 3, 4, 5, 6, 7, 8)
        let boosted = SIMD8<Float>(2, 4, 6, 8, 10, 12, 14, 16)

        let stub = try Stub<any AudioGainProcessor>()
        stub.when(returning: SIMD8<Float>()) {
            $0.applyGain(Match.equal(input), gain: Match.equal(2))
        }.thenReturn(boosted)

        let processor: any AudioGainProcessor = stub()
        #expect(processor.applyGain(input, gain: 2) == boosted)
    }

    @Test func forwardingSpyRecordsCallsWhileDelegatingToTheRealProcessor() throws {
        let input = SIMD8<Float>(1, 1, 1, 1, 1, 1, 1, 1)

        let spy = try Spy<any AudioGainProcessor>(forwardingTo: RealAudioGainProcessor())
        let processor: any AudioGainProcessor = spy()

        #expect(processor.applyGain(input, gain: 3) == SIMD8<Float>(repeating: 3))
        spy.verify(.exactly(1), returning: SIMD8<Float>()) {
            $0.applyGain(Match.any(using: input), gain: Match.equal(3))
        }
    }
}
