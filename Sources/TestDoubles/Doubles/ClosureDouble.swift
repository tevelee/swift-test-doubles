import Foundation
import IssueReporting

/// A configurable, recordable double for an injected synchronous unary
/// closure.
///
/// `ClosureDouble<Input, Result>` represents `(Input) -> Result`; its
/// ``function`` property can be passed directly where that closure type is
/// required. Use a small value type as `Input` when a dependency has several
/// logical inputs.
///
/// ```swift
/// let formatter = ClosureDouble<Int, String>()
/// formatter.when { $0.isMultiple(of: 2) }.thenReturn("even")
/// formatter.whenAny().then { "odd-\($0)" }
/// let format: (Int) -> String = formatter.function
/// ```
public final class ClosureDouble<Input, Result> {
    /// The closure shape represented by this double.
    public typealias Function = (Input) -> Result
    /// Predicate used to select a configured behavior.
    public typealias Matcher = (Input) -> Bool
    /// Typed behavior used to calculate a result.
    public typealias Handler = (Input) -> Result

    private struct Entry {
        let matcher: Matcher?
        let description: String
        let handler: Handler
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var recordedCalls: [Input] = []
    private var behaviorRevision: UInt64 = 0

    /// Creates an empty closure double. Calls require a matching behavior.
    public init() {}

    /// The ordinary closure value, ready to inject into the subject under test.
    public var function: Function {
        { input in self(input) }
    }

    /// Invokes the double. A call is recorded before its configured behavior
    /// runs, matching `Stub`'s observation semantics.
    public func callAsFunction(_ input: Input) -> Result {
        while true {
            let snapshot = lock.withLock {
                (revision: behaviorRevision, entries: entries)
            }
            let matchingIndex = snapshot.entries.firstIndex { entry in
                entry.matcher?(input) ?? true
            }
            let resolution = lock.withLock { () -> (retry: Bool, handler: Handler?) in
                guard behaviorRevision == snapshot.revision else {
                    return (true, nil)
                }
                recordedCalls.append(input)
                return (false, matchingIndex.map { entries[$0].handler })
            }
            if resolution.retry {
                continue
            }
            guard let handler = resolution.handler else {
                let configured = snapshot.entries.map(\.description).joined(separator: ", ")
                preconditionFailure(
                    "[TestDoubles] No matching closure behavior is configured. "
                        + "Register one with `when { ... }.thenReturn(...)` or `whenAny()`."
                        + (configured.isEmpty ? "" : " Configured behaviors: \(configured).")
                )
            }
            return handler(input)
        }
    }

    /// Starts a behavior registration selected by `matcher`.
    public func when(
        _ matcher: @escaping Matcher,
        describedBy description: String = "predicate"
    ) -> Builder {
        Builder(owner: self, matcher: matcher, description: description)
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny() -> Builder {
        Builder(owner: self, matcher: nil, description: "Match.any()")
    }

    /// Every recorded input, in call order.
    public var invocations: [Input] {
        lock.withLock { recordedCalls }
    }

    /// Number of recorded invocations matching `matcher`.
    public func callCount(matching matcher: Matcher) -> Int {
        let calls = lock.withLock { recordedCalls }
        return calls.count(where: matcher)
    }

    /// Verifies how many recorded invocations satisfy `matcher`.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        matching matcher: Matcher,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let actual = callCount(matching: matcher)
        guard expectedCounts.contains(actual) else {
            reportIssue(
                "[TestDoubles] Closure double expected \(callCountDescription(for: expectedCounts)) "
                    + "for \(description), got \(actual).",
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
            return
        }
    }

    /// Verifies that no calls were recorded.
    public func verifyNoInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let count = lock.withLock { recordedCalls.count }
        guard count > 0 else { return }
        reportIssue(
            "[TestDoubles] Expected no closure invocations, got \(count).",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behavior.
    public func clearRecordedInvocations() {
        lock.withLock { recordedCalls.removeAll(keepingCapacity: true) }
    }

    /// Clears configured behavior and recorded invocations.
    public func reset() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            recordedCalls.removeAll(keepingCapacity: true)
            behaviorRevision &+= 1
        }
    }

    /// Configures a closure-double behavior.
    public struct Builder {
        private let owner: ClosureDouble
        private let matcher: Matcher?
        private let description: String

        fileprivate init(owner: ClosureDouble, matcher: Matcher?, description: String) {
            self.owner = owner
            self.matcher = matcher
            self.description = description
        }

        /// Returns `value` for matching invocations.
        public func thenReturn(_ value: Result) {
            then { _ in value }
        }

        /// Computes a result from the closure's typed input.
        public func then(_ handler: @escaping Handler) {
            owner.lock.withLock {
                owner.entries.append(
                    Entry(
                        matcher: matcher,
                        description: description,
                        handler: handler
                    )
                )
                owner.behaviorRevision &+= 1
            }
        }
    }
}

/// A configurable, recordable double for a nullary synchronous closure.
public final class VoidClosureDouble<Result> {
    private let storage = ClosureDouble<Void, Result>()

    /// Creates an empty nullary closure double.
    public init() {}

    /// The ordinary nullary closure ready to inject into a subject.
    public var function: () -> Result { { self() } }

    /// Invokes the double.
    public func callAsFunction() -> Result { storage(()) }

    /// Starts an always-matching behavior registration.
    public func when() -> ClosureDouble<Void, Result>.Builder { storage.whenAny() }

    /// Number of recorded invocations.
    public var callCount: Int { storage.invocations.count }

    /// Verifies that no calls were recorded.
    public func verifyNoInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.verifyNoInteractions(fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

extension ClosureDouble where Input: Equatable {
    /// Starts a behavior registration for an input equal to `value`.
    public func when(equal value: Input) -> Builder {
        when({ $0 == value }, describedBy: "Match.equal(\(String(reflecting: value)))")
    }

    /// Verifies calls that received an input equal to `value`.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        verify(
            expectedCounts,
            matching: { $0 == value },
            describedBy: "Match.equal(\(String(reflecting: value)))",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}
