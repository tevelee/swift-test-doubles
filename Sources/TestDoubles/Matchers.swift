import Foundation

/// Thread-local matcher stack used by free-function matchers.
/// Uses `Thread.current.threadDictionary` for thread safety.
private let matcherStackKey = "_TestDoubles_matcherStack"

var _matcherStack: [ParameterMatcher] {
    get { Thread.current.threadDictionary[matcherStackKey] as? [ParameterMatcher] ?? [] }
    set { Thread.current.threadDictionary[matcherStackKey] = newValue }
}

// MARK: - Matchers

/// Matches any value.
public func any<T>(_ type: T.Type = T.self) -> T {
    _matcherStack.append(AnyMatcher())
    return zeroValue(T.self)
}

/// Matches any value satisfying a predicate.
/// ```swift
/// stub.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
/// ```
public func any<T>(where predicate: @escaping (T) -> Bool) -> T {
    _matcherStack.append(PredicateMatcher(predicate: predicate))
    return zeroValue(T.self)
}

/// Matches a specific equatable value.
public func equal<T: Equatable>(_ value: T) -> T {
    _matcherStack.append(EqualMatcher(expected: value))
    return value
}


// MARK: - Argument Captor

/// Captures argument values during verification for later inspection.
///
/// ```swift
/// let ids = ArgumentCaptor<Int>()
/// stub.verify { $0.find(id: ids.capture()) }.wasCalled(times: 2)
/// XCTAssertEqual(ids.values, [42, 99])
/// XCTAssertEqual(ids.last, 99)
/// ```
public class ArgumentCaptor<T> {
    /// All captured values in call order.
    public var values: [T] = []

    /// The most recently captured value.
    public var last: T? { values.last }

    /// The first captured value.
    public var first: T? { values.first }

    public init() {}

    /// Use in a verify closure to capture the argument at this position.
    public func capture() -> T {
        _matcherStack.append(CaptureMatcher(captor: self))
        return zeroValue(T.self)
    }

    /// Reset captured values.
    public func reset() { values.removeAll() }
}
