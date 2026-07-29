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
        case delayed(FixedResult, Duration, any StubClock)
        case never
        case awaitCancellation(FixedResult?)
        case forward
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

        /// A snapshot of the queue's finite portion. `nil` means a remaining
        /// unbounded behavior will answer every later matching invocation.
        /// This deliberately counts calls, not distinct behavior entries: a
        /// `times: 3` response has three remaining answers.
        func remainingAnswerCount() -> Int? {
            lock.lock()
            defer { lock.unlock() }

            var remaining = 0
            for index in runs.indices where index >= runIndex {
                let run = runs[index]
                switch run.repeatCount {
                    case .unbounded:
                        return nil
                    case .exactly(let count):
                        let consumed = index == runIndex ? consumedInRun : 0
                        remaining += Swift.max(0, count - consumed)
                }
            }
            return remaining
        }

        func isFiniteQueueExhausted() -> Bool {
            remainingAnswerCount() == 0
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
            fatalError(
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
        let matchesEmptyArgumentsExactly: Bool
        let diagnosticSignature: String
        let scenarioName: String?
        let sourceLocation: StubSourceLocation?
        let behavior: Behavior

        init(
            matchers: [ParameterMatcher],
            matchesEmptyArgumentsExactly: Bool = false,
            diagnosticSignature: String,
            scenarioName: String? = nil,
            sourceLocation: StubSourceLocation? = nil,
            behavior: Behavior
        ) {
            self.matchers = matchers
            self.matchesEmptyArgumentsExactly = matchesEmptyArgumentsExactly
            self.diagnosticSignature = diagnosticSignature
            self.scenarioName = scenarioName
            self.sourceLocation = sourceLocation
            self.behavior = behavior
        }
    }

    /// An immutable registration view used while matcher predicates execute
    /// outside the recorder lock. `revision` makes the later dispatch commit
    /// conditional on the same registry still being current.
    struct Snapshot {
        let revision: UInt64
        let entries: [Entry]?
        let exactMatchIndex: ExactMatchIndex?

        func candidateEntryIndices(for args: [Any]) -> [Int]? {
            guard let exactMatchIndex, exactMatchIndex.isWorthUsing else {
                return nil
            }
            return exactMatchIndex.candidateEntryIndices(for: args)
        }
    }

    struct PreparedEntryMatch {
        let entryIndex: Int
        let matcherTransaction: PreparedMatcherTransaction
    }

    struct ShadowingRegistration {
        let signature: String
        let scenarioName: String?
    }

    struct ExactMatchIndex {
        private struct Schema: Hashable {
            let matcherTypes: [ObjectIdentifier]
        }

        private struct Key: Hashable {
            let schema: Schema
            let values: [AnyHashable]
        }

        private var singleDescriptionEntryIndices: [String: [Int]] = [:]
        private var entryIndicesByKey: [Key: [Int]] = [:]
        private var representativeMatchersBySchema: [Schema: [ParameterMatcher]] = [:]
        private var unindexedEntryIndices: [Int] = []
        private var indexedEntryCount = 0

        var isWorthUsing: Bool { indexedEntryCount >= 4 }

        mutating func add(_ entry: Entry, at entryIndex: Int) {
            if entry.matchers.count == 1,
                let matcher = entry.matchers[0] as? DescriptionMatcher
            {
                singleDescriptionEntryIndices[
                    matcher.description,
                    default: []
                ].append(entryIndex)
                indexedEntryCount += 1
                return
            }
            let indexedMatchers = entry.matchers.compactMap {
                $0 as? any ExactMatchIndexable
            }
            guard indexedMatchers.count == entry.matchers.count,
                indexedMatchers.isEmpty == false
            else {
                unindexedEntryIndices.append(entryIndex)
                return
            }
            let schema = Schema(
                matcherTypes: indexedMatchers.map(\.exactMatchIndexSchema)
            )
            let key = Key(
                schema: schema,
                values: indexedMatchers.map(\.exactMatchIndexValue)
            )
            entryIndicesByKey[key, default: []].append(entryIndex)
            representativeMatchersBySchema[schema] = entry.matchers
            indexedEntryCount += 1
        }

        func candidateEntryIndices(for args: [Any]) -> [Int] {
            var candidates = unindexedEntryIndices
            if args.count == 1 {
                candidates.append(
                    contentsOf: singleDescriptionEntryIndices[
                        String(describing: args[0])
                    ] ?? []
                )
            }
            for (schema, matchers) in representativeMatchersBySchema {
                guard matchers.count == args.count else { continue }
                let values = zip(matchers, args).compactMap { matcher, argument in
                    (matcher as? any ExactMatchIndexable)?
                        .exactMatchIndexValue(for: argument)
                }
                guard values.count == args.count else { continue }
                candidates.append(
                    contentsOf: entryIndicesByKey[
                        Key(schema: schema, values: values)
                    ] ?? []
                )
            }
            candidates.sort()
            return candidates
        }
    }

    private var entriesByMethod: [Int: [Entry]] = [:]
    private var exactMatchIndicesByMethod: [Int: ExactMatchIndex] = [:]
    private var consumedEntryIndicesByMethod: [Int: Set<Int>] = [:]
    private var revision: UInt64 = 0

    func snapshot(for method: Int) -> Snapshot {
        Snapshot(
            revision: revision,
            entries: entriesByMethod[method],
            exactMatchIndex: exactMatchIndicesByMethod[method]
        )
    }

    func isCurrent(_ snapshot: Snapshot) -> Bool {
        revision == snapshot.revision
    }

    mutating func removeAll() {
        entriesByMethod.removeAll()
        exactMatchIndicesByMethod.removeAll()
        consumedEntryIndicesByMethod.removeAll()
        revision &+= 1
    }

    /// Marks a registration as having answered at least one call. Entries are
    /// append-only between `removeAll` calls, so the index is a stable
    /// identity.
    mutating func markConsumed(method: Int, entryIndex: Int) {
        consumedEntryIndicesByMethod[method, default: []].insert(entryIndex)
    }

    /// Returns the diagnostic signatures of registrations that never answered
    /// a call, in registration order per method.
    func unusedRegistrationSignatures() -> [String] {
        entriesByMethod.sorted { $0.key < $1.key }.flatMap { method, entries in
            entries.enumerated().compactMap { index, entry in
                consumedEntryIndicesByMethod[method]?.contains(index) == true
                    ? nil
                    : entry.diagnosticSignature
            }
        }
    }

    mutating func add(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false,
        diagnosticSignature: String,
        scenarioName: String? = nil,
        sourceLocation: StubSourceLocation? = nil,
        behavior: Entry.Behavior
    ) {
        let entryIndex = entriesByMethod[method]?.count ?? 0
        let entry = Entry(
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
            diagnosticSignature: diagnosticSignature,
            scenarioName: scenarioName,
            sourceLocation: sourceLocation,
            behavior: behavior
        )
        entriesByMethod[method, default: []].append(
            entry
        )
        exactMatchIndicesByMethod[method, default: ExactMatchIndex()]
            .add(entry, at: entryIndex)
        revision &+= 1
    }

    /// Prepares the first registered matching entry, like the first matching
    /// case of a `switch`: register specific matchers before broad fallbacks.
    /// User predicates and projections are evaluated exactly once here.
    static func firstPreparedEntryMatch(
        for args: [Any],
        in entries: [Entry],
        candidateEntryIndices: [Int]? = nil
    ) -> PreparedEntryMatch? {
        func preparedMatch(at entryIndex: Int) -> PreparedEntryMatch? {
            let entry = entries[entryIndex]
            if let matcherTransaction = prepareArgumentsMatch(
                args,
                against: entry.matchers,
                matchesEmptyArgumentsExactly: entry.matchesEmptyArgumentsExactly
            ) {
                return PreparedEntryMatch(
                    entryIndex: entryIndex,
                    matcherTransaction: matcherTransaction
                )
            }
            return nil
        }
        if let candidateEntryIndices {
            for entryIndex in candidateEntryIndices {
                if let match = preparedMatch(at: entryIndex) {
                    return match
                }
            }
        } else {
            for entryIndex in entries.indices {
                if let match = preparedMatch(at: entryIndex) {
                    return match
                }
            }
        }
        return nil
    }

    /// Reports the diagnostic signature of an already-registered entry for
    /// `method` that provably shadows a new registration with `newMatchers`,
    /// or `nil` when none does. A shadowing entry accepts a superset of the
    /// calls the new one would, so under first-match-wins the new one can
    /// never be selected.
    func shadowingSignature(
        forMethod method: Int,
        newMatchers: [ParameterMatcher],
        newMatchesEmptyArgumentsExactly: Bool = false
    ) -> ShadowingRegistration? {
        let entry = entriesByMethod[method]?
            .first {
                StubBehaviorRegistry.matchesSuperset(
                    $0.matchers,
                    matchesEmptyArgumentsExactly: $0.matchesEmptyArgumentsExactly,
                    of: newMatchers,
                    matchesEmptyArgumentsExactly: newMatchesEmptyArgumentsExactly
                )
            }
        return entry.map {
            ShadowingRegistration(signature: $0.diagnosticSignature, scenarioName: $0.scenarioName)
        }
    }

    /// Whether `earlier` accepts every call `later` would, proven soundly.
    ///
    /// An empty matcher list is normally a universal catch-all. An explicitly
    /// empty parameter pack instead accepts only a call with no flattened
    /// values. Otherwise every position of `earlier` must accept a superset
    /// of the same position in `later`: either it accepts any value, or both
    /// positions are value matchers with the identical accepted set.
    /// Opaque predicates yield `nil` identities and never satisfy the rule, so
    /// a real shadow through them is missed rather than a reachable
    /// registration falsely flagged.
    static func matchesSuperset(
        _ earlier: [ParameterMatcher],
        matchesEmptyArgumentsExactly earlierMatchesEmptyArgumentsExactly: Bool = false,
        of later: [ParameterMatcher],
        matchesEmptyArgumentsExactly laterMatchesEmptyArgumentsExactly: Bool = false
    ) -> Bool {
        if earlier.isEmpty {
            return earlierMatchesEmptyArgumentsExactly == false
                || (later.isEmpty && laterMatchesEmptyArgumentsExactly)
        }
        guard earlier.count == later.count else { return false }
        return zip(earlier, later).allSatisfy { earlierMatcher, laterMatcher in
            earlierMatcher.acceptsAnyValue
                || (earlierMatcher.acceptanceIdentity != nil
                    && earlierMatcher.acceptanceIdentity == laterMatcher.acceptanceIdentity)
        }
    }

    static func argumentsMatch(
        _ args: [Any],
        against matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false
    ) -> Bool {
        prepareArgumentsMatch(
            args,
            against: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
        ) != nil
    }

    static func prepareArgumentsMatch(
        _ args: [Any],
        against matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false
    ) -> PreparedMatcherTransaction? {
        if matchers.isEmpty {
            return matchesEmptyArgumentsExactly && args.isEmpty == false ? nil : .matched
        }
        guard args.count == matchers.count else {
            return nil
        }
        var combined = PreparedMatcherTransaction.matched
        for (value, matcher) in zip(args, matchers) {
            guard let transaction = matcher.prepareMatch(value: value) else { return nil }
            combined.append(transaction)
        }
        return combined
    }
}

extension StubRecorder {
    typealias ConsumableResults = StubBehaviorRegistry.ConsumableResults
    typealias StubEntry = StubBehaviorRegistry.Entry
    typealias QueuedAnswer = StubBehaviorRegistry.QueuedAnswer
    typealias RepeatCount = StubBehaviorRegistry.RepeatCount
}
