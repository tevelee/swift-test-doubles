import CTestDoublesTrampoline
import Echo

/// Owns one dynamic call frame and its optional result/error value buffers.
/// Buffer state prevents failure paths from destroying uninitialized memory
/// and prevents moved values from being destroyed a second time.
final class ManagedDynamicCall: @unchecked Sendable {
    let rawFrame: UnsafeMutablePointer<TDCallFrame>
    let result: ManagedValueBuffer
    let error: ManagedValueBuffer?

    var frame: TrampolineCallFrame { TrampolineCallFrame(rawFrame) }

    init(resultType: Any.Type, errorType: Any.Type?) {
        rawFrame = .allocate(capacity: 1)
        UnsafeMutableRawPointer(rawFrame).initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: MemoryLayout<TDCallFrame>.size
        )
        result = ManagedValueBuffer(type: resultType)
        error = errorType.map { ManagedValueBuffer(type: $0) }
    }

    /// Completes the ownership transition for values returned through the
    /// captured frame. Direct values are copied out of return registers;
    /// indirect values already occupy their caller-provided buffers.
    func finish(
        resultLayout: ABIClass,
        typedErrorLayout: ABIClass?,
        typedErrorUsesIndirectResultSlot: Bool
    ) {
        if frame.returnedError == 0 {
            decodeDirectResult(
                resultLayout,
                frame: rawFrame,
                into: result.storage
            )
            result.markInitialized()
            return
        }

        guard let error else { return }
        if typedErrorUsesIndirectResultSlot == false {
            guard let typedErrorLayout else {
                preconditionFailure(
                    "[TestDoubles] A typed closure returned no error layout."
                )
            }
            decodeDirectResult(
                typedErrorLayout,
                frame: rawFrame,
                into: error.storage
            )
        }
        error.markInitialized()
    }

    deinit {
        rawFrame.deallocate()
    }
}
