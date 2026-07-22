import Testing
@testable import TestDoubles

private final class AccessorFinishRecorder {
    var abortValues: [Bool] = []
}

private final class TestYieldingAccessorState:
    YieldingAccessorState,
    @unchecked Sendable
{
    let kind: YieldingAccessorKind
    let yieldedStorage: UnsafeMutableRawPointer? = nil
    private let recorder: AccessorFinishRecorder

    init(
        kind: YieldingAccessorKind,
        recorder: AccessorFinishRecorder
    ) {
        self.kind = kind
        self.recorder = recorder
    }

    func finish(isAborting: Bool) {
        recorder.abortValues.append(isAborting)
    }
}

@Suite struct YieldingAccessorRuntimeTests {
    @Test func readStateIsRetainedUntilNormalResumption() {
        exerciseRetainedState(kind: .read, isAborting: false)
    }

    @Test func modifyStateReceivesAbortBeforeRelease() {
        exerciseRetainedState(kind: .modify, isAborting: true)
    }

    private func exerciseRetainedState(
        kind: YieldingAccessorKind,
        isAborting: Bool
    ) {
        let recorder = AccessorFinishRecorder()
        var state: TestYieldingAccessorState? = TestYieldingAccessorState(
            kind: kind,
            recorder: recorder
        )
        weak let weakState = state
        let retained = YieldingAccessorRuntime.retain(state!)
        state = nil

        #expect(weakState != nil)
        YieldingAccessorRuntime.finish(
            retained,
            as: kind,
            isAborting: isAborting,
            invalidTypeMessage: "invalid test state"
        )

        #expect(recorder.abortValues == [isAborting])
        #expect(weakState == nil)
    }
}
