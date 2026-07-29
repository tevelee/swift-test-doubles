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
        private let transform: (RecordedCall) -> Element
        private var lastSeenCallID: UInt64?

        init(
            recorder: StubRecorder,
            recording: RecordedCall,
            origin: InvocationOrigin?,
            startingAfter lastSeenCallID: UInt64?,
            transform: @escaping (RecordedCall) -> Element
        ) {
            self.recorder = recorder
            self.recording = recording
            self.origin = origin
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
                return nil
            }
            lastSeenCallID = call.id
            return transform(call)
        }

        /// Waits up to `timeout` for the next matching invocation.
        ///
        /// Returns `nil` when the timeout expires or the awaiting task is
        /// cancelled. Use the clock-aware overload with ``ManualStubClock``
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
                return nil
            }
            lastSeenCallID = call.id
            return transform(call)
        }
    }

    private let recorder: StubRecorder
    private let recording: RecordedCall
    private let origin: InvocationOrigin?
    private let startAfterCallID: UInt64?
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
        startAfterCallID = recorder.latestRecordedCallID()
        self.transform = transform
    }

    /// Creates an iterator that observes calls after this stream was created.
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            recorder: recorder,
            recording: recording,
            origin: origin,
            startingAfter: startAfterCallID,
            transform: transform
        )
    }
}
