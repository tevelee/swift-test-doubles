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
        error = errorType.map(ManagedValueBuffer.init(type:))
    }

    deinit {
        rawFrame.deallocate()
    }
}

final class ManagedValueBuffer: @unchecked Sendable {
    private enum State {
        case uninitialized
        case initialized
        case consumed
    }

    let metadata: Metadata
    let storage: UnsafeMutableRawPointer
    private var state = State.uninitialized

    init(type: Any.Type) {
        metadata = reflect(type)
        storage = metadata.allocateValueBuffer()
    }

    func zeroBytes() {
        storage.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: metadata.valueBufferByteCount()
        )
    }

    func markInitialized() {
        precondition(state == .uninitialized)
        state = .initialized
    }

    func markConsumed() {
        precondition(state == .initialized)
        state = .consumed
    }

    deinit {
        if state == .initialized {
            metadata.vwt.destroy(storage)
        }
        storage.deallocate()
    }
}
