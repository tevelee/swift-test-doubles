import Foundation

/// One task-local capture buffer. Its small lock permits child tasks in the
/// same capture context to append safely without involving recorder state.
private final class StubCaptureSession: @unchecked Sendable {
    let recorder: StubRecorder
    let parent: StubCaptureSession?

    private let lock = NSLock()
    private var calls: [RecordedCall] = []

    init(recorder: StubRecorder, parent: StubCaptureSession?) {
        self.recorder = recorder
        self.parent = parent
    }

    func append(_ call: RecordedCall) {
        lock.lock()
        calls.append(call)
        lock.unlock()
    }

    func takeCalls() -> [RecordedCall] {
        lock.lock()
        defer { lock.unlock() }
        let result = calls
        calls.removeAll(keepingCapacity: true)
        return result
    }
}

/// Coordinates nested synchronous and asynchronous capture scopes without
/// owning or borrowing the recorder's state lock.
enum StubCaptureCoordinator {
    @TaskLocal private static var activeSession: StubCaptureSession?

    static func isCapturing(_ recorder: StubRecorder) -> Bool {
        session(for: recorder) != nil
    }

    static func capture(
        recorder: StubRecorder,
        _ operation: () -> Void
    ) -> [RecordedCall] {
        precondition(
            session(for: recorder) == nil,
            "[TestDoubles] Stub capture operations must not overlap."
        )
        let session = StubCaptureSession(recorder: recorder, parent: activeSession)
        $activeSession.withValue(session) {
            operation()
        }
        return session.takeCalls()
    }

    static func capture(
        recorder: StubRecorder,
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async -> Void
    ) async -> [RecordedCall] {
        precondition(
            session(for: recorder) == nil,
            "[TestDoubles] Stub capture operations must not overlap."
        )
        let session = StubCaptureSession(recorder: recorder, parent: activeSession)
        await $activeSession.withValue(session) {
            await operation()
        }
        return session.takeCalls()
    }

    static func append(
        _ call: RecordedCall,
        to recorder: StubRecorder
    ) {
        guard let session = session(for: recorder) else {
            preconditionFailure("[TestDoubles] No Stub capture operation is active.")
        }
        session.append(call)
    }

    private static func session(for recorder: StubRecorder) -> StubCaptureSession? {
        var session = activeSession
        while let current = session {
            if current.recorder === recorder {
                return current
            }
            session = current.parent
        }
        return nil
    }
}
