/// A snapshot of closure arguments consumed without tuple indexing.
///
/// The argument pack stays fully typed while `forEach`, `map`, and `reduce`
/// pass every closure argument as a separate parameter.
///
/// ```swift
/// let calls = pattern.argumentHistory()
/// let descriptions = calls.map { count, label in
///     "\(count) \(label)"
/// }
/// ```
public struct ClosureArgumentHistory<Input> {
    private let values: [Input]

    init(_ values: [Input]) {
        self.values = values
    }

    /// Number of recorded argument lists in this snapshot.
    public var count: Int {
        values.count
    }

    /// Whether this snapshot contains no argument lists.
    public var isEmpty: Bool {
        values.isEmpty
    }

    /// Calls `body` once for every recorded argument list.
    public func forEach<each Argument>(
        _ body: (repeat each Argument) throws -> Void
    ) rethrows
    where Input == (repeat each Argument) {
        func apply(
            _ value: (repeat each Argument)
        ) throws {
            try body(repeat each value)
        }
        try values.forEach(apply)
    }

    /// Transforms every recorded argument list.
    public func map<each Argument, Output>(
        _ transform: (repeat each Argument) throws -> Output
    ) rethrows -> [Output]
    where Input == (repeat each Argument) {
        func apply(
            _ value: (repeat each Argument)
        ) throws -> Output {
            try transform(repeat each value)
        }
        return try values.map(apply)
    }

    /// Combines every recorded argument list into one value.
    public func reduce<each Argument, Output>(
        _ initialResult: Output,
        _ nextPartialResult:
            (
                Output,
                repeat each Argument
            ) throws -> Output
    ) rethrows -> Output
    where Input == (repeat each Argument) {
        func apply(
            _ partialResult: Output,
            _ value: (repeat each Argument)
        ) throws -> Output {
            try nextPartialResult(
                partialResult,
                repeat each value
            )
        }
        return try values.reduce(initialResult, apply)
    }
}

extension ClosureArgumentHistory: Sendable where Input: Sendable {}

extension ClosureCallPattern {
    /// Returns a tuple-free typed snapshot of matching argument lists.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(arguments())
    }
}

extension ThrowingClosureCallPattern {
    /// Returns a tuple-free typed snapshot of matching argument lists.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(arguments())
    }
}

extension AsyncClosureCallPattern {
    /// Returns a tuple-free typed snapshot of matching argument lists.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(arguments())
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Returns a tuple-free typed snapshot of matching argument lists.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(arguments())
    }
}

extension ClosureDouble {
    /// Returns a tuple-free typed snapshot of every recorded argument list.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(invocations)
    }
}

extension ThrowingClosureDouble {
    /// Returns a tuple-free typed snapshot of every recorded argument list.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(invocations)
    }
}

extension AsyncClosureDouble {
    /// Returns a tuple-free typed snapshot of every recorded argument list.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(invocations)
    }
}

extension AsyncThrowingClosureDouble {
    /// Returns a tuple-free typed snapshot of every recorded argument list.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(invocations)
    }
}

extension TypedThrowingClosureDouble {
    /// Returns a tuple-free typed snapshot of every recorded argument list.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(invocations)
    }
}

extension AsyncTypedThrowingClosureDouble {
    /// Returns a tuple-free typed snapshot of every recorded argument list.
    public func argumentHistory() -> ClosureArgumentHistory<Input> {
        ClosureArgumentHistory(invocations)
    }
}
