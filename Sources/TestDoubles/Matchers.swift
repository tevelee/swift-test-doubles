/// Thread-local matcher stack used by free-function matchers.
/// Populated by `any()`, `equal()`, `match()` and consumed by `RuntimeStub.when`.
///
/// Note: `_matcherStack` is designed for single-threaded test execution.
/// The record/consume cycle within `RuntimeStub.when` is not synchronized;
/// concurrent calls from multiple threads would corrupt the stack.
nonisolated(unsafe) var _matcherStack: [ParameterMatcher] = []

/// Matches any value.
public func any<T>(_ type: T.Type = T.self) -> T {
    _matcherStack.append(AnyMatcher())
    return zeroValue(T.self)
}

/// Matches a specific equatable value.
public func equal<T: Equatable>(_ value: T) -> T {
    _matcherStack.append(EqualMatcher(expected: value))
    return value
}

/// Matches values passing a predicate.
public func match<T>(_ predicate: @escaping (T) -> Bool) -> T {
    _matcherStack.append(PredicateMatcher(predicate: predicate))
    return zeroValue(T.self)
}
