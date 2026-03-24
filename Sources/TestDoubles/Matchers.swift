import Foundation

/// Thread-local matcher stack used by free-function matchers.
/// Populated by `any()`, `equal()`, `match()` and consumed by `RuntimeStub.when`.
///
/// Uses `Thread.current.threadDictionary` for thread safety — safe for
/// XCTest parallel execution in Xcode 16+.
private let matcherStackKey = "_TestDoubles_matcherStack"

var _matcherStack: [ParameterMatcher] {
    get {
        Thread.current.threadDictionary[matcherStackKey] as? [ParameterMatcher] ?? []
    }
    set {
        Thread.current.threadDictionary[matcherStackKey] = newValue
    }
}

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
