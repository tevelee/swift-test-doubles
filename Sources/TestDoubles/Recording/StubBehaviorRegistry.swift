import Foundation

/// Lock-agnostic behavior storage owned and synchronized by ``StubRecorder``.
struct StubBehaviorRegistry {
    typealias FixedResult = Result<Any, any Error>

    /// Serves queued fixed results one per matching invocation, repeating the
    /// final result once the earlier entries are consumed.
    final class ConsumableResults: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [FixedResult]
        private var nextIndex = 0

        init(_ results: [FixedResult]) {
            precondition(results.isEmpty == false)
            self.results = results
        }

        func append(_ result: FixedResult) {
            lock.lock()
            results.append(result)
            lock.unlock()
        }

        func append(contentsOf additionalResults: [FixedResult]) {
            lock.lock()
            results.append(contentsOf: additionalResults)
            lock.unlock()
        }

        func next() -> FixedResult {
            lock.lock()
            defer { lock.unlock() }
            let result = results[nextIndex]
            if nextIndex < results.index(before: results.endIndex) {
                nextIndex += 1
            }
            return result
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

            /// Reserves the next queued result while the recorder is committing
            /// the invocation. Other behaviors are immutable selections.
            func reservingSequenceResult() -> Self {
                switch self {
                    case .fixedSequence(let results):
                        .fixed(results.next())
                    default:
                        self
                }
            }
        }

        let matchers: [ParameterMatcher]
        let diagnosticSignature: String
        let behavior: Behavior
        let specificity: Int

        init(
            matchers: [ParameterMatcher],
            diagnosticSignature: String,
            behavior: Behavior
        ) {
            self.matchers = matchers
            self.diagnosticSignature = diagnosticSignature
            self.behavior = behavior
            self.specificity = matchers.reduce(0) { $0 + $1.specificity }
        }
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

    /// Returns the first registered entry among those with the highest matcher
    /// specificity.
    static func bestMatchingEntry(
        for args: [Any],
        in entries: [Entry]
    ) -> Entry? {
        var bestEntry: Entry?
        var bestSpecificity = -1
        for entry in entries
        where entry.matchers.isEmpty || argumentsMatch(args, against: entry.matchers) {
            if entry.specificity > bestSpecificity {
                bestSpecificity = entry.specificity
                bestEntry = entry
            }
        }
        return bestEntry
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
}
