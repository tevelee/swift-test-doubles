/// A chronological, diagnostic view of a test double's observed calls.
///
/// The timeline is intentionally observational: reading it neither verifies
/// calls nor changes behavior-chain consumption. Each event records the
/// dispatch decision made at the call boundary and the task priority observed
/// there. Swift does not expose a stable task identity or current actor for
/// arbitrary synchronous code, so those are deliberately not guessed at.
public struct InteractionTimeline: Sendable, CustomStringConvertible {
    /// Whether a call was answered by a configured registration or delegated
    /// by a ``Spy`` to its target.
    public enum Dispatch: String, Sendable {
        /// A configured registration answered the call.
        case stubbed
        /// A spy delegated the call to its target.
        case forwarded

        /// Creates a dispatch path from its serialized representation.
        public init?(rawValue: String) {
            switch rawValue {
                case "stubbed":
                    self = .stubbed
                case "forwarded":
                    self = .forwarded
                default:
                    return nil
            }
        }
    }

    /// One call-boundary event in global process order.
    public struct Event: Sendable, Identifiable {
        /// A coarse completion state that does not expose recorded values.
        public enum Outcome: Sendable, Hashable {
            /// The invocation has entered but not completed.
            case pending
            /// The invocation returned normally.
            case returned
            /// The invocation threw an error.
            case threw
            /// A spy delegated the invocation to its target.
            case forwarded
            /// The invocation's result could not be recorded.
            case unavailable
        }

        /// The process-global order shared by all test doubles.
        public let id: UInt64
        /// The process-global completion order, or `nil` while pending.
        public let completionSequence: UInt64?
        /// The requirement name, with its ordinary Swift argument labels.
        public let requirement: String
        /// Arguments rendered for diagnostics.
        public let arguments: [String]
        /// The selected dispatch path.
        public let dispatch: Dispatch
        /// The selected registration, when a stubbed behavior answered it.
        public let registration: String?
        /// The task priority observed when the call entered the double.
        public let taskPriorityRawValue: UInt8
        /// Captured call-stack symbols, when capture was enabled.
        public let callStack: [String]?
        /// The monotonic instant at which the call entered the double.
        public let startedAt: ContinuousClock.Instant
        /// The monotonic instant at which the call completed.
        public let completedAt: ContinuousClock.Instant?
        /// Elapsed time from entry to completion, or `nil` while pending.
        public let duration: Duration?
        /// The invocation's coarse completion state.
        public let outcome: Outcome
        /// Whether the invocation completed by throwing an error.
        public var didThrow: Bool { outcome == .threw }
    }

    /// Events in global call order.
    public let events: [Event]

    init(calls: [RecordedCall], orderedByCompletion: Bool = false) {
        let orderedCalls =
            if orderedByCompletion {
                calls.sorted {
                    ($0.completionSequence ?? .max)
                        < ($1.completionSequence ?? .max)
                }
            } else {
                calls
            }
        events = orderedCalls.compactMap { call in
            guard let sequence = call.sequence, let startedAt = call.startedAt else {
                return nil
            }
            return Event(
                id: sequence,
                completionSequence: call.completionSequence,
                requirement: call.name,
                arguments: call.args.map { String(reflecting: $0) },
                dispatch: call.origin == .forwarded ? .forwarded : .stubbed,
                registration: call.registrationSignature,
                taskPriorityRawValue: call.taskPriorityRawValue,
                callStack: call.callStack,
                startedAt: startedAt,
                completedAt: call.completedAt,
                duration: call.completedAt.map { startedAt.duration(to: $0) },
                outcome: Event.Outcome(call.outcome)
            )
        }
    }

    init(events: [Event]) {
        self.events = events
    }

    /// A compact, human-readable trace suitable for test-failure output.
    public var description: String {
        guard events.isEmpty == false else {
            return "[TestDoubles] No interaction timeline events recorded."
        }
        return
            (["[TestDoubles] Interaction timeline:"]
            + events.map { event in
                let arguments = event.arguments.joined(separator: ", ")
                let registration = event.registration.map { " via \($0)" } ?? ""
                return "  #\(event.id) \(event.dispatch.rawValue) \(event.requirement)(\(arguments))\(registration)"
            }).joined(separator: "\n")
    }
}

extension InteractionTimeline.Event.Outcome {
    init(_ outcome: RecordedCallOutcome) {
        switch outcome {
            case .pending: self = .pending
            case .returned: self = .returned
            case .threw: self = .threw
            case .forwarded: self = .forwarded
            case .unavailable: self = .unavailable
        }
    }
}

extension StubRecorder {
    func interactionTimeline() -> InteractionTimeline {
        InteractionTimeline(calls: withLockedPolicy { $0.invocationLedger.allCalls })
    }
}

extension Stub {
    /// Returns an ordered diagnostic trace of every observed invocation.
    public func interactionTimeline() -> InteractionTimeline {
        recorder.interactionTimeline()
    }
}

extension ManualStub {
    /// Returns an ordered diagnostic trace of every observed invocation.
    public func interactionTimeline() -> InteractionTimeline {
        recorder.interactionTimeline()
    }
}
