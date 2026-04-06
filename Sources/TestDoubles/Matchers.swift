import Foundation

/// Thread-keyed matcher stack for free-function matchers (any(), equal(), etc.).
enum MatcherContext {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stacks: [UInt: [ParameterMatcher]] = [:]

    private static var key: UInt {
        UInt(bitPattern: Unmanaged.passUnretained(Thread.current).toOpaque())
    }

    static func begin() {
        lock.lock()
        stacks[key] = []
        lock.unlock()
    }

    static func append(_ matcher: ParameterMatcher) {
        lock.lock()
        stacks[key, default: []].append(matcher)
        lock.unlock()
    }

    static func end() -> [ParameterMatcher] {
        lock.lock()
        let result = stacks.removeValue(forKey: key) ?? []
        lock.unlock()
        return result
    }
}

/// Matches any argument of type `T`. Use inside ``when(_:)`` and ``verify(_:)`` closures.
public func any<T>(_ type: T.Type = T.self) -> T {
    MatcherContext.append(AnyMatcher())
    return zeroValue(T.self)
}

/// Matches any argument of type `T` that satisfies `predicate`.
public func any<T>(where predicate: @escaping (T) -> Bool) -> T {
    MatcherContext.append(PredicateMatcher(predicate: predicate))
    return zeroValue(T.self)
}

/// Matches an argument that is equal to `value`.
public func equal<T: Equatable>(_ value: T) -> T {
    MatcherContext.append(EqualMatcher(expected: value))
    return value
}

/// Captures argument values for later inspection.
///
/// Use ``capture()`` inside a ``verify(_:)`` closure to record each value the method was called with:
///
/// ```swift
/// let captor = ArgumentCaptor<Int>()
/// stub.verify { $0.find(id: captor.capture()) }.wasCalled(times: 2)
/// assert(captor.values == [1, 42])
/// ```
public class ArgumentCaptor<T> {
    /// All captured values, in call order.
    public var values: [T] = []
    /// The most recently captured value.
    public var last: T? { values.last }
    /// The first captured value.
    public var first: T? { values.first }
    public init() {}

    /// Returns a matcher placeholder that records each matching argument into ``values``.
    public func capture() -> T {
        MatcherContext.append(CaptureMatcher(captor: self))
        return zeroValue(T.self)
    }

    /// Removes all previously captured values.
    public func reset() { values.removeAll() }
}
