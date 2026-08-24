/// A structured issue discovered while checking a test-double scope.
///
/// Test integrations can switch on ``kind`` while continuing to present the
/// stable human-readable ``description``.
public struct TestDoubleIssue: Sendable, CustomStringConvertible {
    /// The condition that produced an issue.
    public enum Kind: Sendable, Hashable {
        /// A configured registration matched no invocation.
        case unusedRegistrations
        /// A recorded interaction was not successfully verified.
        case unverifiedInteractions
        /// A finite behavior queue still contains planned answers.
        case unconsumedBehaviorQueue
        /// A suspended invocation has not been resumed.
        case pendingSuspension
        /// A callback capture still owns undelivered callbacks.
        case pendingCallbackCapture
        /// A generated double value or controller outlived its scope.
        case escapedTestDouble
        /// An asynchronous invocation has not completed.
        case unfinishedAsyncInvocations
        /// An invocation stream has matching calls left unread.
        case unconsumedInvocationStream
        /// A controlled stream was neither finished nor cancelled.
        case openStreamController
    }

    /// The condition that produced this issue.
    public let kind: Kind

    /// The actionable diagnostic without a test-double name prefix.
    public let message: String

    /// The user-assigned or scope-generated test-double name, when available.
    public let testDoubleName: String?

    /// Creates a structured test-double issue.
    public init(
        kind: Kind,
        message: String,
        testDoubleName: String? = nil
    ) {
        self.kind = kind
        self.message = message
        self.testDoubleName = testDoubleName
    }

    /// The existing user-facing diagnostic text.
    public var description: String {
        guard let testDoubleName else { return message }
        return "Test double '\(testDoubleName)':\n\(message)"
    }
}
