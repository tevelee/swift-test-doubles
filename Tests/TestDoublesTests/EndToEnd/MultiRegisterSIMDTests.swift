import Testing
import TestDoubles

/// End-to-end coverage for multi-register SIMD arguments/results using a
/// real-world-shaped protocol: a batch audio gain processor, the kind of API
/// that genuinely passes an 8-wide sample vector (two 128-bit registers) in
/// hot DSP code. See ABI_VALIDATION_NOTES.md Section 3 for the ABI
/// background.
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
            $0.applyGain(equal(input), gain: equal(2))
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
            $0.applyGain(any(using: input), gain: equal(3))
        }
    }
}
