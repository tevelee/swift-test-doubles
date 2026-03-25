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

public func any<T>(_ type: T.Type = T.self) -> T {
    MatcherContext.append(AnyMatcher())
    return zeroValue(T.self)
}

public func any<T>(where predicate: @escaping (T) -> Bool) -> T {
    MatcherContext.append(PredicateMatcher(predicate: predicate))
    return zeroValue(T.self)
}

public func equal<T: Equatable>(_ value: T) -> T {
    MatcherContext.append(EqualMatcher(expected: value))
    return value
}

public class ArgumentCaptor<T> {
    public var values: [T] = []
    public var last: T? { values.last }
    public var first: T? { values.first }
    public init() {}

    public func capture() -> T {
        MatcherContext.append(CaptureMatcher(captor: self))
        return zeroValue(T.self)
    }

    public func reset() { values.removeAll() }
}
