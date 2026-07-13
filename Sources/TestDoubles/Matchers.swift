import Foundation

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

enum MatcherContext {
    @TaskLocal private static var activeRecording: MatcherRecording?

    static func withRecording<Result>(
        _ operation: () throws -> Result
    ) rethrows -> (result: Result, matchers: [ParameterMatcher]) {
        let recording = MatcherRecording()
        let result = try $activeRecording.withValue(recording) {
            try operation()
        }
        return (result, recording.matchers)
    }

    static func withRecording<Result>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> Result
    ) async rethrows -> (result: Result, matchers: [ParameterMatcher]) {
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

/// Matches any argument of type `T`.
public func any<T>() -> T {
    MatcherContext.append(AnyMatcher())
    return zeroValue(T.self)
}

/// Matches an argument that is equal to `value`.
public func equal<T: Equatable>(_ value: T) -> T {
    MatcherContext.append(EqualMatcher(expected: value))
    return value
}

/// Matches an argument accepted by `predicate`.
public func matching<T>(
    description: String = "predicate",
    where predicate: @escaping (T) -> Bool
) -> T {
    MatcherContext.append(PredicateMatcher(description: description, predicate: predicate))
    return zeroValue(T.self)
}

/// Captures matching argument values for later inspection.
public final class ArgumentCaptor<T> {
    private let lock = NSLock()
    private var storage: [T] = []

    /// All captured values, in call order.
    public var values: [T] { withLock { storage } }

    /// The first captured value.
    public var first: T? { withLock { storage.first } }

    /// The most recently captured value.
    public var last: T? { withLock { storage.last } }

    /// Creates an empty captor.
    public init() {}

    /// Returns a matcher placeholder that captures each matching argument.
    public func capture() -> T {
        MatcherContext.append(CaptureMatcher(captor: self))
        return zeroValue(T.self)
    }

    /// Removes all previously captured values.
    public func reset() {
        withLock { storage.removeAll() }
    }

    func append(_ value: T) {
        withLock { storage.append(value) }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
