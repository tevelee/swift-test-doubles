import Foundation

/// Lock-agnostic behavior storage owned and synchronized by ``StubRecorder``.
struct StubBehaviorRegistry {
    typealias FixedResult = Result<Any, any Error>

    /// How many consecutive matching calls a single queued answer serves
    /// before the sequence advances to the next one.
    enum RepeatCount {
        case exactly(Int)
        case unbounded
    }

    /// A single queued answer: a fixed value/error delivered immediately or
    /// after a delay, a park that never completes, a park that completes on
    /// task cancellation, or an explicit crash for whichever call reaches it.
    /// A `nil` cancellation outcome resolves at dispatch: a throwing
    /// requirement rethrows the cancellation, a `Void` requirement returns.
    enum QueuedAnswer {
        case value(FixedResult)
        case delayed(FixedResult, Duration)
        case never
        case awaitCancellation(FixedResult?)
        case fatal(message: String?)
    }

    /// Serves queued answers one per matching invocation. Exact-count runs
    /// advance when exhausted if there is a next run. Bounded terminal runs
    /// fail once their own count is exceeded.
    final class ConsumableResults: @unchecked Sendable {
        private struct Run {
            let answer: QueuedAnswer
            let repeatCount: RepeatCount
        }

        private let lock = NSLock()
        private var runs: [Run]
        private var runIndex = 0
        private var consumedInRun = 0

        init(_ answers: [(QueuedAnswer, RepeatCount)]) {
            precondition(answers.isEmpty == false)
            self.runs = answers.map { Run(answer: $0.0, repeatCount: $0.1) }
        }

        func append(_ answer: QueuedAnswer, times repeatCount: RepeatCount) {
            lock.lock()
            defer { lock.unlock() }
            requireNotSealed()
            runs.append(Run(answer: answer, repeatCount: repeatCount))
        }

        func append(contentsOf answers: [QueuedAnswer]) {
            lock.lock()
            defer { lock.unlock() }
            requireNotSealed()
            runs.append(contentsOf: answers.map { Run(answer: $0, repeatCount: .exactly(1)) })
        }

        /// An unbounded run already answers every call from here on, so a
        /// fluent chain can never type-check an append after one — the
        /// unbounded overloads return `Void`. A captured, explicitly
        /// type-annotated handle can still reach this call, though, since the
        /// annotation forces the compiler to select the chain-returning
        /// overload regardless of what followed at the original call site.
        /// This is the same mistake either way, so it gets the same
        /// crash-with-diagnostic treatment as every other "there is no
        /// sensible value here" situation in this library.
        private func requireNotSealed() {
            guard case .unbounded = runs.last?.repeatCount else { return }
            preconditionFailure(
                "[TestDoubles] Cannot append another behavior after an unbounded one; "
                    + "it already answers every matching call from here on, so anything "
                    + "appended after it could never run."
            )
        }

        func next() -> QueuedAnswer {
            lock.lock()
            defer { lock.unlock() }
            let run = runs[runIndex]
            consumedInRun += 1

            switch run.repeatCount {
                case .exactly(let count):
                    if consumedInRun > count {
                        if runIndex < runs.index(before: runs.endIndex) {
                            runIndex += 1
                            consumedInRun = 1
                            return runs[runIndex].answer
                        }
                        return .fatal(
                            message: "Bounded stub behavior exhausted after exactly "
                                + "\(count) matching calls."
                        )
                    }
                case .unbounded:
                    break
            }
            return run.answer
        }
    }

    struct Entry {
        enum Behavior {
            case fixed(FixedResult)
            case fixedSequence(ConsumableResults)
            case immediate(@Sendable ([Any]) throws -> Any)
            // This function type remains non-Sendable so Swift preserves the
            // actor/executor on which the user formed an async handler.
            case suspending(([Any]) async throws -> Any)
        }

        let matchers: [ParameterMatcher]
        let diagnosticSignature: String
        let behavior: Behavior
    }

    private var entriesByMethod: [Int: [Entry]] = [:]

    func entries(for method: Int) -> [Entry]? {
        entriesByMethod[method]
    }

    mutating func add(
        method: Int,
        matchers: [ParameterMatcher],
        diagnosticSignature: String,
        behavior: Entry.Behavior
    ) {
        entriesByMethod[method, default: []].append(
            Entry(
                matchers: matchers,
                diagnosticSignature: diagnosticSignature,
                behavior: behavior
            ))
    }

    /// Returns the first registered matching entry, like the first matching
    /// case of a `switch`: register specific matchers before broad fallbacks.
    static func firstMatchingEntry(
        for args: [Any],
        in entries: [Entry]
    ) -> Entry? {
        entries.first { entry in
            entry.matchers.isEmpty || argumentsMatch(args, against: entry.matchers)
        }
    }

    static func argumentsMatch(
        _ args: [Any],
        against matchers: [ParameterMatcher]
    ) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }

    static func commitCaptures(
        in args: [Any],
        against matchers: [ParameterMatcher]
    ) {
        zip(args, matchers).forEach { value, matcher in
            matcher.commit(value: value)
        }
    }
}

extension StubRecorder {
    typealias ConsumableResults = StubBehaviorRegistry.ConsumableResults
    typealias StubEntry = StubBehaviorRegistry.Entry
    typealias QueuedAnswer = StubBehaviorRegistry.QueuedAnswer
    typealias RepeatCount = StubBehaviorRegistry.RepeatCount
}
