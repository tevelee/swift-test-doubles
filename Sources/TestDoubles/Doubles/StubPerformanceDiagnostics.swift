/// A point-in-time performance snapshot for a runtime-generated stub or spy.
///
/// Construction durations distinguish reusable protocol-plan preparation from
/// recorder and existential materialization. Dispatch durations are end-to-end
/// latency: they include matcher selection, before-call hooks, handler
/// suspension, and spy forwarding rather than representing CPU time.
public struct StubPerformanceDiagnostics: Sendable, CustomStringConvertible {
    /// Timings captured while the stub or spy was constructed.
    public struct Construction: Sendable {
        /// Time spent looking up or preparing the reusable protocol plan.
        public let planPreparationDuration: Duration
        /// Time spent creating the recorder and materializing the generated value.
        public let materializationDuration: Duration
        /// Total measured construction time.
        public let totalDuration: Duration

        init(
            planPreparationDuration: Duration,
            materializationDuration: Duration
        ) {
            self.planPreparationDuration = planPreparationDuration
            self.materializationDuration = materializationDuration
            totalDuration = planPreparationDuration + materializationDuration
        }
    }

    /// Aggregate dispatch latency for one requirement name.
    public struct MethodDispatch: Sendable {
        /// The requirement's diagnostic name.
        public let method: String
        /// All recorded calls, including calls that remain pending.
        public let callCount: Int
        /// Calls that returned, threw, or completed forwarding.
        public let completedCallCount: Int
        /// Calls that have not completed.
        public let pendingCallCount: Int
        /// Total latency of completed calls.
        public let totalDuration: Duration
        /// Mean latency of completed calls, or `nil` when none completed.
        public let averageDuration: Duration?
        /// Greatest latency among completed calls, or `nil` when none completed.
        public let maximumDuration: Duration?
    }

    /// Aggregate latency for every dispatch recorded by the double.
    public struct Dispatch: Sendable {
        /// All recorded calls, including calls that remain pending.
        public let callCount: Int
        /// Calls that returned, threw, or completed forwarding.
        public let completedCallCount: Int
        /// Calls that have not completed.
        public let pendingCallCount: Int
        /// Total latency of completed calls.
        public let totalDuration: Duration
        /// Mean latency of completed calls, or `nil` when none completed.
        public let averageDuration: Duration?
        /// Greatest latency among completed calls, or `nil` when none completed.
        public let maximumDuration: Duration?
        /// Requirement aggregates ordered by greatest latency, then name.
        public let methods: [MethodDispatch]
    }

    /// Timings captured by this double's construction.
    public let construction: Construction
    /// Current aggregate dispatch latency.
    public let dispatch: Dispatch

    /// A compact construction and dispatch report.
    public var description: String {
        var lines = [
            "Construction: \(construction.totalDuration) total "
                + "(\(construction.planPreparationDuration) preparation, "
                + "\(construction.materializationDuration) materialization)"
        ]
        if dispatch.callCount == 0 {
            lines.append("Dispatch: no calls")
            return lines.joined(separator: "\n")
        }
        lines.append(
            "Dispatch: \(dispatch.callCount) calls "
                + "(\(dispatch.completedCallCount) completed, "
                + "\(dispatch.pendingCallCount) pending), "
                + "\(dispatch.totalDuration) total"
        )
        for method in dispatch.methods {
            let maximum = method.maximumDuration.map(String.init(describing:)) ?? "pending"
            lines.append(
                "  \(method.method): \(method.callCount) calls, max \(maximum)"
            )
        }
        return lines.joined(separator: "\n")
    }
}

extension StubRecorder {
    func dispatchPerformanceDiagnostics() -> StubPerformanceDiagnostics.Dispatch {
        struct Aggregate {
            var callCount = 0
            var completedCallCount = 0
            var totalDuration = Duration.zero
            var maximumDuration: Duration?

            mutating func record(_ call: RecordedCall) {
                callCount += 1
                guard
                    let startedAt = call.startedAt,
                    let completedAt = call.completedAt
                else {
                    return
                }
                let duration = startedAt.duration(to: completedAt)
                completedCallCount += 1
                totalDuration += duration
                maximumDuration = max(maximumDuration ?? duration, duration)
            }
        }

        let calls = interactionHistoryCalls(origin: nil)
        var total = Aggregate()
        var byMethod = [String: Aggregate]()
        for call in calls {
            total.record(call)
            byMethod[call.name, default: Aggregate()].record(call)
        }
        let methods = byMethod.map { method, aggregate in
            StubPerformanceDiagnostics.MethodDispatch(
                method: method,
                callCount: aggregate.callCount,
                completedCallCount: aggregate.completedCallCount,
                pendingCallCount: aggregate.callCount - aggregate.completedCallCount,
                totalDuration: aggregate.totalDuration,
                averageDuration: aggregate.completedCallCount == 0
                    ? nil
                    : aggregate.totalDuration / aggregate.completedCallCount,
                maximumDuration: aggregate.maximumDuration
            )
        }.sorted {
            let left = $0.maximumDuration ?? .zero
            let right = $1.maximumDuration ?? .zero
            return left == right ? $0.method < $1.method : left > right
        }
        return StubPerformanceDiagnostics.Dispatch(
            callCount: total.callCount,
            completedCallCount: total.completedCallCount,
            pendingCallCount: total.callCount - total.completedCallCount,
            totalDuration: total.totalDuration,
            averageDuration: total.completedCallCount == 0
                ? nil
                : total.totalDuration / total.completedCallCount,
            maximumDuration: total.maximumDuration,
            methods: methods
        )
    }
}

extension Stub {
    /// A point-in-time construction and dispatch performance snapshot.
    ///
    /// Reading the snapshot does not mutate or verify interaction history.
    public var performanceDiagnostics: StubPerformanceDiagnostics {
        StubPerformanceDiagnostics(
            construction: constructionPerformance,
            dispatch: recorder.dispatchPerformanceDiagnostics()
        )
    }
}
