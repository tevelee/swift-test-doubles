import Foundation

private final class MatcherRecording: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ParameterMatcher] = []

    func append(_ matcher: ParameterMatcher) {
        lock.lock()
        storage.append(matcher)
        lock.unlock()
    }

    func takeMatchers() -> [ParameterMatcher] {
        lock.lock()
        defer { lock.unlock() }
        let matchers = storage
        storage.removeAll(keepingCapacity: true)
        return matchers
    }
}

enum MatcherContext {
    @TaskLocal private static var activeRecording: MatcherRecording?

    static func withRecording<Result, Failure: Error>(
        _ operation: () throws(Failure) -> Result
    ) throws(Failure) -> (result: Result, remainingMatchers: [ParameterMatcher]) {
        let recording = MatcherRecording()
        let result: Result
        do {
            result = try $activeRecording.withValue(recording) {
                do {
                    return try operation()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure("[TestDoubles] Task-local matcher storage unexpectedly threw \(error).")
        }
        return (result, recording.takeMatchers())
    }

    static func withRecording<Result, Failure: Error>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws(Failure) -> Result
    ) async throws(Failure) -> (result: Result, remainingMatchers: [ParameterMatcher]) {
        let recording = MatcherRecording()
        let result: Result
        do {
            result = try await $activeRecording.withValue(recording) {
                do {
                    return try await operation()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure("[TestDoubles] Task-local matcher storage unexpectedly threw \(error).")
        }
        return (result, recording.takeMatchers())
    }

    static func append(_ matcher: ParameterMatcher) {
        activeRecording?.append(matcher)
    }

    /// Removes and returns the matchers formed since the previous captured
    /// invocation. Argument evaluation completes before trampoline dispatch, so
    /// all pending matchers belong to the invocation entering the recorder.
    static func takeMatchers() -> [ParameterMatcher] {
        activeRecording?.takeMatchers() ?? []
    }
}

/// Matches any argument of type `T`.
///
/// This overload synthesizes a valid recording placeholder. For reference,
/// existential, or other unsupported types, use ``any(using:)``.
public func any<T>() -> T {
    MatcherContext.append(AnyMatcher())
    return synthesizedPlaceholder(for: "any()", fallback: "any(using:)")
}

/// Matches any argument of type `T`, using `placeholder` while recording the call.
///
/// Use this overload when ``any()`` cannot safely synthesize a value, such as
/// for reference or existential types. The placeholder is never used for matching.
///
/// - Parameter placeholder: A valid value accepted by the stubbed requirement.
public func any<T>(using placeholder: T) -> T {
    MatcherContext.append(AnyMatcher())
    return placeholder
}

/// Matches an argument that is equal to `value`.
public func equal<T: Equatable>(_ value: T) -> T {
    MatcherContext.append(EqualMatcher(expected: value))
    return value
}

/// Matches an argument accepted by `predicate`.
///
/// This overload synthesizes a valid recording placeholder. For reference,
/// existential, or other unsupported types, use ``matching(using:description:where:)``.
public func matching<T>(
    description: String = "predicate",
    where predicate: @escaping @Sendable (T) -> Bool
) -> T {
    MatcherContext.append(PredicateMatcher(description: description, predicate: predicate))
    return synthesizedPlaceholder(
        for: "matching(description:where:)",
        fallback: "matching(using:description:where:)"
    )
}

/// Matches an argument accepted by `predicate`, using `placeholder` while recording the call.
///
/// The placeholder is never evaluated by the matcher and is not used for matching.
///
/// - Parameters:
///   - placeholder: A valid value accepted by the stubbed requirement.
///   - description: A diagnostic description of the predicate.
///   - predicate: A closure that determines whether an actual argument matches.
public func matching<T>(
    using placeholder: T,
    description: String = "predicate",
    where predicate: @escaping @Sendable (T) -> Bool
) -> T {
    MatcherContext.append(PredicateMatcher(description: description, predicate: predicate))
    return placeholder
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
    ///
    /// This overload synthesizes a valid recording placeholder. For reference,
    /// existential, or other unsupported types, use ``capture(using:)``.
    public func capture() -> T {
        MatcherContext.append(CaptureMatcher(captor: self))
        return synthesizedPlaceholder(for: "capture()", fallback: "capture(using:)")
    }

    /// Returns a matcher placeholder that captures each matching argument.
    ///
    /// Use this overload when ``capture()`` cannot safely synthesize a value,
    /// such as for reference or existential types. The placeholder is never captured.
    ///
    /// - Parameter placeholder: A valid value accepted by the stubbed requirement.
    public func capture(using placeholder: T) -> T {
        MatcherContext.append(CaptureMatcher(captor: self))
        return placeholder
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

/// A captor uses a lock to serialize its storage. It can cross concurrency
/// domains only when its captured values can do so safely as well.
extension ArgumentCaptor: @unchecked Sendable where T: Sendable {}

/// Synthesizes the recording placeholder a matcher returns at its call site,
/// or traps pointing at the `using:` overload that accepts a caller-supplied
/// value.
private func synthesizedPlaceholder<T>(for api: String, fallback: String) -> T {
    guard let placeholder = PlaceholderValue.make(T.self) else {
        preconditionFailure(
            "[TestDoubles] \(api) cannot safely synthesize a placeholder for \(T.self). "
                + "Pass a valid value with \(fallback) instead."
        )
    }
    return placeholder
}
