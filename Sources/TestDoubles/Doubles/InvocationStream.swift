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
        private let transform: (RecordedCall) -> Element
        private var lastSeenCallID: UInt64?

        init(
            recorder: StubRecorder,
            recording: RecordedCall,
            startingAfter lastSeenCallID: UInt64?,
            transform: @escaping (RecordedCall) -> Element
        ) {
            self.recorder = recorder
            self.recording = recording
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
                    matching: recording
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
    private let startAfterCallID: UInt64?
    private let transform: (RecordedCall) -> Element

    init(
        recorder: StubRecorder,
        recording: RecordedCall,
        transform: @escaping (RecordedCall) -> Element
    ) {
        self.recorder = recorder
        self.recording = recording
        startAfterCallID = recorder.latestRecordedCallID()
        self.transform = transform
    }

    /// Creates an iterator that observes calls after this stream was created.
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            recorder: recorder,
            recording: recording,
            startingAfter: startAfterCallID,
            transform: transform
        )
    }
}
