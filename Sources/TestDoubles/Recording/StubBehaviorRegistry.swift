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

    /// A single queued answer: either a fixed value/error, or an explicit
    /// crash for whichever call reaches it.
    enum QueuedAnswer {
        case value(FixedResult)
        case fatal(message: String?)
    }

    /// Serves queued answers one per matching invocation, repeating the final
    /// run once the earlier ones are consumed. A bounded run with nothing
    /// after it keeps repeating too, exactly like an unbounded run — only an
    /// explicit next run advances the cursor past it.
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
            runs.append(Run(answer: answer, repeatCount: repeatCount))
            lock.unlock()
        }

        func append(contentsOf answers: [QueuedAnswer]) {
            lock.lock()
            runs.append(contentsOf: answers.map { Run(answer: $0, repeatCount: .exactly(1)) })
            lock.unlock()
        }

        func next() -> QueuedAnswer {
            lock.lock()
            defer { lock.unlock() }
            let run = runs[runIndex]
            consumedInRun += 1
            if case .exactly(let count) = run.repeatCount,
                consumedInRun >= count,
                runIndex < runs.index(before: runs.endIndex)
            {
                runIndex += 1
                consumedInRun = 0
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
