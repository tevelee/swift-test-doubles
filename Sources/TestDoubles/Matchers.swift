import Foundation

/// A typed reusable predicate matcher.
///
/// Use ``matching(_:)`` to apply a matcher inside ``when(_:)`` or ``verify(_:)``:
///
/// ```swift
/// let vipID = Matcher<Int>("VIP id") { $0 > 100 }
/// stub.when { $0.find(id: matching(vipID)) }.returns("VIP")
/// ```
public struct Matcher<Value>: CustomStringConvertible {
    private let predicate: (Value) -> Bool

    /// Human-readable matcher name used in failure diagnostics.
    public let description: String

    /// Creates a matcher with a diagnostic `description` and a predicate.
    public init(_ description: String, _ predicate: @escaping (Value) -> Bool) {
        self.description = description
        self.predicate = predicate
    }

    /// Returns `true` when this matcher accepts `value`.
    public func matches(_ value: Value) -> Bool {
        predicate(value)
    }
}

private final class MatcherRecording: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ParameterMatcher] = []

    func append(_ matcher: ParameterMatcher) {
        lock.lock()
        storage.append(matcher)
        lock.unlock()
    }

    var matchers: [ParameterMatcher] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Task-local matcher stack for free-function matchers (any(), equal(), etc.).
enum MatcherContext {
    @TaskLocal private static var activeRecording: MatcherRecording?

    static func withRecording<T>(_ operation: () throws -> T) rethrows -> (result: T, matchers: [ParameterMatcher]) {
        let recording = MatcherRecording()
        let result = try $activeRecording.withValue(recording) {
            try operation()
        }
        return (result, recording.matchers)
    }

    static func withRecording<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async rethrows -> (result: T, matchers: [ParameterMatcher]) {
        let recording = MatcherRecording()
        let result = try await $activeRecording.withValue(recording) {
            try await operation()
        }
        return (result, recording.matchers)
    }

    static func append(_ matcher: ParameterMatcher) {
        activeRecording?.append(matcher)
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

/// Matches any argument of type `T` accepted by `matcher`.
public func matching<T>(_ matcher: Matcher<T>) -> T {
    MatcherContext.append(TypedMatcher(matcher: matcher))
    return zeroValue(T.self)
}

/// Matches any argument of type `T` accepted by `predicate`.
public func matching<T>(_ description: String, _ predicate: @escaping (T) -> Bool) -> T {
    matching(Matcher(description, predicate))
}

/// Matches an argument that is equal to `value`.
public func equal<T: Equatable>(_ value: T) -> T {
    MatcherContext.append(EqualMatcher(expected: value))
    return value
}

/// Captures argument values into `captor` for later inspection.
public func capture<T>(into captor: ArgumentCaptor<T>) -> T {
    captor.capture()
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
