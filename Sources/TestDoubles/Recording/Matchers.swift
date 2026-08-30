import Foundation
import InternalRuntimeContract

private final class MatcherRecording: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ParameterMatcher] = []
    private var calibrations: [RuntimeArgumentCalibration] = []

    func append(_ matcher: ParameterMatcher) {
        lock.lock()
        storage.append(matcher)
        lock.unlock()
    }

    func appendCalibration<T>(_ placeholder: borrowing T) {
        lock.lock()
        calibrations.append(RuntimeArgumentCalibration(placeholder: placeholder))
        lock.unlock()
    }

    func currentCalibrations() -> [RuntimeArgumentCalibration] {
        lock.lock()
        defer { lock.unlock() }
        return calibrations
    }

    func takeMatchers() -> [ParameterMatcher] {
        takeRecording().matchers
    }

    func takeRecording() -> (matchers: [ParameterMatcher], calibrations: [RuntimeArgumentCalibration]) {
        lock.lock()
        defer { lock.unlock() }
        let matchers = storage
        let recordedCalibrations = calibrations
        storage.removeAll(keepingCapacity: true)
        calibrations.removeAll(keepingCapacity: true)
        return (matchers, recordedCalibrations)
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

    /// Records the exact value returned by the most recently appended
    /// top-level matcher before the caller applies its concrete ABI.
    @inline(never)
    static func returning<T>(_ placeholder: T) -> T {
        activeRecording?.appendCalibration(placeholder)
        RuntimeStubFactory.scrubArgumentRegisters()
        return placeholder
    }

    static func currentCalibrations() -> [RuntimeArgumentCalibration] {
        activeRecording?.currentCalibrations() ?? []
    }

    /// Runs `body` against a fresh sub-recording and returns the matchers it
    /// appended without leaking them into the enclosing invocation's list.
    ///
    /// Combinators such as ``Match/not(_:)`` and ``Match/allOf(_:_:)`` use this to fold the
    /// matchers their nested expressions record into one composite matcher, so
    /// a composed argument stays a single positional matcher.
    static func captureNested<Result>(
        _ body: () -> Result
    ) -> (result: Result, matchers: [ParameterMatcher]) {
        let recording = MatcherRecording()
        let result = $activeRecording.withValue(recording) { body() }
        return (result, recording.takeMatchers())
    }

    /// Removes and returns the matchers formed since the previous captured
    /// invocation. Argument evaluation completes before trampoline dispatch, so
    /// all pending matchers belong to the invocation entering the recorder.
    static func takeMatchers() -> [ParameterMatcher] {
        activeRecording?.takeMatchers() ?? []
    }

    /// Removes and returns the matchers formed since the previous captured
    /// invocation together with the concrete placeholder bytes Swift passed
    /// to the requirement. The paired calibration is used only to prove a
    /// unique argument position for mixed literal-and-matcher recordings.
    static func takeRecording() -> (
        matchers: [ParameterMatcher],
        calibrations: [RuntimeArgumentCalibration]
    ) {
        activeRecording?.takeRecording() ?? ([], [])
    }
}

/// Namespaces argument matchers, captures, and recording placeholders.
///
/// Every matcher returns the argument's own type so it can be written directly
/// inside a call-recording closure. Keeping the vocabulary under one namespace
/// makes available matchers discoverable through autocomplete without
/// occupying the module's global function namespace.
public enum Match {}

/// Captures matching argument values for later inspection.
///
/// Pass ``capture()`` or ``capture(using:)`` inside a `when` or `verify`
/// expression, then inspect the snapshot returned by ``values``.
public final class ArgumentCaptor<Value> {
    private let lock = NSLock()
    private var storage: [Value] = []

    /// All captured values, in call order.
    public var values: [Value] { withLock { storage } }

    /// The first captured value.
    public var first: Value? { withLock { storage.first } }

    /// The most recently captured value.
    public var last: Value? { withLock { storage.last } }

    /// Creates an empty argument captor.
    public init() {}

    /// Returns a matcher placeholder that captures each matching argument.
    ///
    /// This overload synthesizes a valid recording placeholder. For reference,
    /// existential, or other unsupported types, use ``capture(using:)``.
    public func capture() -> Value {
        MatcherContext.append(CaptureMatcher(captor: self))
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "ArgumentCaptor.capture()",
                fallback: "ArgumentCaptor.capture(using:)"
            )
        )
    }

    /// Returns a matcher placeholder that captures each matching argument.
    ///
    /// Use this overload when ``capture()`` cannot safely synthesize a value.
    /// The placeholder is never captured.
    public func capture(using placeholder: Value) -> Value {
        MatcherContext.append(CaptureMatcher(captor: self))
        return MatcherContext.returning(placeholder)
    }

    /// Removes all previously captured values.
    public func removeAll() {
        withLock { storage.removeAll() }
    }

    /// Removes all previously captured values.
    public func reset() {
        removeAll()
    }

    func append(_ value: Value) {
        withLock { storage.append(value) }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

/// An argument captor uses a lock to serialize its storage. It can cross
/// concurrency domains when its captured values can do so safely as well.
extension ArgumentCaptor: @unchecked Sendable where Value: Sendable {}

extension Match {
    /// Matches any argument of type `T`.
    ///
    /// This overload synthesizes a valid recording placeholder, including for
    /// common standard-library and framework values and recursively populated
    /// generic wrappers. For reference, existential, or other unsupported types,
    /// use ``Match/any(using:)``.
    public static func any<T>() -> T {
        MatcherContext.append(AnyMatcher())
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "Match.any()",
                fallback: "Match.any(using:)"
            )
        )
    }

    /// Matches any argument of type `T`, using `placeholder` while recording the call.
    ///
    /// Use this overload when ``Match/any()`` cannot safely synthesize a value, such as
    /// for reference or existential types. The placeholder is never used for matching.
    ///
    /// - Parameter placeholder: A valid value accepted by the stubbed requirement.
    public static func any<T>(using placeholder: T) -> T {
        MatcherContext.append(AnyMatcher())
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument that is equal to `value`.
    public static func equal<T: Equatable>(_ value: T) -> T {
        MatcherContext.append(EqualMatcher(expected: value))
        return MatcherContext.returning(value)
    }

    /// Matches an argument accepted by `predicate`.
    ///
    /// This overload synthesizes a valid recording placeholder. For reference,
    /// existential, or other unsupported types, use
    /// ``Match/matching(using:description:where:)``.
    public static func matching<T>(
        description: String = "predicate",
        where predicate: @escaping @Sendable (T) -> Bool
    ) -> T {
        MatcherContext.append(PredicateMatcher(description: description, predicate: predicate))
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "Match.matching(description:where:)",
                fallback: "Match.matching(using:description:where:)"
            )
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
    public static func matching<T>(
        using placeholder: T,
        description: String = "predicate",
        where predicate: @escaping @Sendable (T) -> Bool
    ) -> T {
        MatcherContext.append(PredicateMatcher(description: description, predicate: predicate))
        return MatcherContext.returning(placeholder)
    }

    /// Compatibility spelling for ``ArgumentCaptor``.
    public typealias Capture<Value> = ArgumentCaptor<Value>
}

/// Synthesizes the recording placeholder a matcher returns at its call site,
/// preferring a suite-wide registered factory, or traps pointing at the
/// `using:` overload that accepts a caller-supplied value.
func synthesizedPlaceholder<T>(for api: String, fallback: String) -> T {
    guard let placeholder = RecordingPlaceholderResolver.make(T.self) else {
        fatalError(
            "[TestDoubles] \(api) cannot safely synthesize a placeholder for \(T.self). "
                + "Pass a valid value with \(fallback), or register a suite-wide "
                + "factory with Match.Placeholders.register."
        )
    }
    return placeholder
}
