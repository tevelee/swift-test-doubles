import Foundation

/// One recorder-tagged call from a multi-double capture scope.
struct CapturedStubCall: @unchecked Sendable {
    let recorder: StubRecorder
    let call: RecordedCall
}

/// One task-local capture buffer. Its small lock permits child tasks in the
/// same capture context to append safely without involving recorder state.
private final class StubCaptureSession: @unchecked Sendable {
    let recorder: StubRecorder?
    let parent: StubCaptureSession?

    private let lock = NSLock()
    private var calls: [CapturedStubCall] = []

    init(recorder: StubRecorder?, parent: StubCaptureSession?) {
        self.recorder = recorder
        self.parent = parent
    }

    func append(_ call: RecordedCall, from recorder: StubRecorder) {
        lock.lock()
        calls.append(CapturedStubCall(recorder: recorder, call: call))
        lock.unlock()
    }

    func takeCalls() -> [CapturedStubCall] {
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
        return session.takeCalls().map(\.call)
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
        return session.takeCalls().map(\.call)
    }

    static func captureAll<Result, Failure: Error>(
        _ operation: () throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let session = StubCaptureSession(recorder: nil, parent: activeSession)
        let result: Result
        do {
            result = try $activeSession.withValue(session) {
                do {
                    return try operation()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure(
                "[TestDoubles] Task-local invocation capture unexpectedly "
                    + "threw \(error)."
            )
        }
        precondition(
            session.takeCalls().isEmpty,
            "[TestDoubles] Every invocation in an InvocationOrder builder must "
                + "be a separate expression."
        )
        return result
    }

    static func captureAll<Result, Failure: Error>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        let session = StubCaptureSession(recorder: nil, parent: activeSession)
        let result: Result
        do {
            result = try await $activeSession.withValue(session) {
                do {
                    return try await operation()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure(
                "[TestDoubles] Task-local invocation capture unexpectedly "
                    + "threw \(error)."
            )
        }
        precondition(
            session.takeCalls().isEmpty,
            "[TestDoubles] Every invocation in an InvocationOrder builder must "
                + "be a separate expression."
        )
        return result
    }

    static func takeBuilderCall() -> CapturedStubCall? {
        guard let session = activeSession, session.recorder == nil else {
            return nil
        }
        let calls = session.takeCalls()
        precondition(
            calls.count <= 1,
            "[TestDoubles] Each InvocationOrder builder expression must invoke "
                + "exactly one protocol requirement."
        )
        return calls.first
    }

    static func append(
        _ call: RecordedCall,
        to recorder: StubRecorder
    ) {
        guard let session = session(for: recorder) else {
            preconditionFailure("[TestDoubles] No Stub capture operation is active.")
        }
        session.append(call, from: recorder)
    }

    private static func session(for recorder: StubRecorder) -> StubCaptureSession? {
        var session = activeSession
        while let current = session {
            if current.recorder == nil || current.recorder === recorder {
                return current
            }
            session = current.parent
        }
        return nil
    }
}
