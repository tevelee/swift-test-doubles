import Foundation

/// Lock-agnostic behavior storage owned and synchronized by ``StubRecorder``.
struct StubBehaviorRegistry {
    /// Serves queued return values one per matching invocation, repeating the
    /// final value once the earlier entries are consumed.
    final class ConsumableValues: @unchecked Sendable {
        private let lock = NSLock()
        private let values: [Any]
        private var nextIndex = 0

        init(_ values: [Any]) {
            precondition(values.isEmpty == false)
            self.values = values
        }

        func next() -> Any {
            lock.lock()
            defer { lock.unlock() }
            let value = values[nextIndex]
            if nextIndex < values.index(before: values.endIndex) {
                nextIndex += 1
            }
            return value
        }
    }

    struct Entry {
        enum Behavior {
            case value(Any)
            case valueSequence(ConsumableValues)
            case immediate(@Sendable ([Any]) throws -> Any)
            // This function type remains non-Sendable so Swift preserves the
            // actor/executor on which the user formed an async handler.
            case suspending(([Any]) async throws -> Any)

            /// Reserves the next queued value while the recorder is committing
            /// the invocation. Other behaviors are immutable selections.
            func reservingSequenceValue() -> Self {
                switch self {
                    case .valueSequence(let values):
                        .value(values.next())
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
    typealias ConsumableValues = StubBehaviorRegistry.ConsumableValues
    typealias StubEntry = StubBehaviorRegistry.Entry
}
