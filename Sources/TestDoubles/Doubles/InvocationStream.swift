import Foundation

private final class InvocationStreamConsumptionState: @unchecked Sendable {
    private let recorder: StubRecorder
    private let recording: RecordedCall
    private let origin: InvocationOrigin?
    private let startAfterCallID: UInt64?
    private let lock = NSLock()
    private var consumedCallIDs: Set<UInt64> = []
    private var isTerminated = false

    init(
        recorder: StubRecorder,
        recording: RecordedCall,
        origin: InvocationOrigin?,
        startingAfter startAfterCallID: UInt64?
    ) {
        self.recorder = recorder
        self.recording = recording
        self.origin = origin
        self.startAfterCallID = startAfterCallID
    }

    func recordConsumption(of call: RecordedCall) {
        guard let id = call.id else { return }
        _ = lock.withLock {
            consumedCallIDs.insert(id)
        }
    }

    func terminate() {
        lock.withLock {
            isTerminated = true
        }
    }

    func teardownDiagnostic() -> String? {
        let snapshot = lock.withLock {
            (consumedCallIDs, isTerminated)
        }
        guard snapshot.1 == false else { return nil }

        let unreadCalls = recorder.verificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            origin: origin
        ).filter { call in
            guard let id = call.id else { return false }
            if let startAfterCallID, id <= startAfterCallID {
                return false
            }
            return snapshot.0.contains(id) == false
        }
        guard unreadCalls.isEmpty == false else { return nil }

        let count = unreadCalls.count
        let subject = recorder.testDoubleName.map { " for test double '\($0)'" } ?? ""
        return "Expected the invocation stream\(subject) for \(recording.name) to consume "
            + "every matching call, but \(count) unread "
            + "\(count == 1 ? "invocation remains" : "invocations remain")."
    }
}

/// An asynchronous sequence of future invocations matching one requirement.
///
/// Create a stream with ``CallPattern/stream()``. A stream observes calls made after it
/// is created, in recorded order. It is a pure observation: yielding a call
/// does not mark it verified or commit argument captors.
public struct InvocationStream<Element>: AsyncSequence {
    /// The iterator used to receive matching invocations.
    public struct Iterator: AsyncIteratorProtocol {
        private let recorder: StubRecorder
        private let recording: RecordedCall
        private let origin: InvocationOrigin?
        private let consumptionState: InvocationStreamConsumptionState
        private let transform: (RecordedCall) -> Element
        private var lastSeenCallID: UInt64?

        fileprivate init(
            recorder: StubRecorder,
            recording: RecordedCall,
            origin: InvocationOrigin?,
            consumptionState: InvocationStreamConsumptionState,
            startingAfter lastSeenCallID: UInt64?,
            transform: @escaping (RecordedCall) -> Element
        ) {
            self.recorder = recorder
            self.recording = recording
            self.origin = origin
            self.consumptionState = consumptionState
            self.lastSeenCallID = lastSeenCallID
            self.transform = transform
        }

        /// Waits for and returns the next matching invocation.
        ///
        /// Returns `nil` when the awaiting task is cancelled. Calls already
        /// recorded when the stream was created are deliberately excluded.
        public mutating func next() async -> Element? {
            guard
                let call = await recorder.nextMatchingInvocation(
                    after: lastSeenCallID,
                    matching: recording,
                    origin: origin
                )
            else {
                if Task.isCancelled {
                    consumptionState.terminate()
                }
                return nil
            }
            lastSeenCallID = call.id
            consumptionState.recordConsumption(of: call)
            return transform(call)
        }

        /// Waits up to `timeout` for the next matching invocation.
        ///
        /// Returns `nil` when the timeout expires or the awaiting task is
        /// cancelled. Use the clock-aware overload with ``TestDoubleClock``
        /// when the timeout itself must be deterministic.
        public mutating func next(within timeout: Duration) async -> Element? {
            await next(within: timeout, using: StubClocks.continuous)
        }

        /// Waits for the next matching invocation using `clock`.
        ///
        /// Returns `nil` when the timeout expires or the awaiting task is
        /// cancelled.
        public mutating func next(
            within timeout: Duration,
            using clock: any StubClock
        ) async -> Element? {
            guard
                let call = await recorder.nextMatchingInvocation(
                    after: lastSeenCallID,
                    matching: recording,
                    origin: origin,
                    within: timeout,
                    using: clock
                )
            else {
                if Task.isCancelled {
                    consumptionState.terminate()
                }
                return nil
            }
            lastSeenCallID = call.id
            consumptionState.recordConsumption(of: call)
            return transform(call)
        }
    }

    private let recorder: StubRecorder
    private let recording: RecordedCall
    private let origin: InvocationOrigin?
    private let startAfterCallID: UInt64?
    private let consumptionState: InvocationStreamConsumptionState
    private let transform: (RecordedCall) -> Element

    init(
        recorder: StubRecorder,
        recording: RecordedCall,
        origin: InvocationOrigin? = nil,
        transform: @escaping (RecordedCall) -> Element
    ) {
        self.recorder = recorder
        self.recording = recording
        self.origin = origin
        let startAfterCallID = recorder.latestRecordedCallID()
        self.startAfterCallID = startAfterCallID
        let consumptionState = InvocationStreamConsumptionState(
            recorder: recorder,
            recording: recording,
            origin: origin,
            startingAfter: startAfterCallID
        )
        self.consumptionState = consumptionState
        self.transform = transform
        TestDoubleTestingContext.session?.register(
            TestDoubleTeardownCheck(kind: .invocationStream) {
                consumptionState.teardownDiagnostic()
            }
        )
    }

    /// Creates an iterator that observes calls after this stream was created.
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            recorder: recorder,
            recording: recording,
            origin: origin,
            consumptionState: consumptionState,
            startingAfter: startAfterCallID,
            transform: transform
        )
    }
}
