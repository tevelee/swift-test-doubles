import Foundation
import InternalRuntimeContract

/// The calibration recorded for a closure-shaped `Match.any()`, whose
/// placeholder has no abstractable bytes. It locates any function-typed
/// argument: closures have no equality, so such an argument always carries a
/// `Match` expression.
struct FunctionPlaceholderCalibration {}

private final class MatcherRecording: @unchecked Sendable {
    /// Matchers an `@autoclosure` argument formed when the forwarding
    /// implementation evaluated it, after every eager argument.
    private struct DeferredGroup {
        let position: Int
        let matchers: [ParameterMatcher]
        let calibrations: [RuntimeArgumentCalibration]
    }

    private let lock = NSLock()
    private var storage: [ParameterMatcher] = []
    private var calibrations: [RuntimeArgumentCalibration] = []
    private var deferred: [DeferredGroup] = []

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

    func appendDeferred(
        at position: Int,
        matchers: [ParameterMatcher],
        calibrations: [RuntimeArgumentCalibration]
    ) {
        lock.lock()
        deferred.append(
            DeferredGroup(position: position, matchers: matchers, calibrations: calibrations)
        )
        lock.unlock()
    }

    func takeRecording(
        argumentCount: Int? = nil
    ) -> (matchers: [ParameterMatcher], calibrations: [RuntimeArgumentCalibration]) {
        lock.lock()
        defer { lock.unlock() }
        var matchers = storage
        var recordedCalibrations = calibrations
        let groups = deferred.sorted { $0.position < $1.position }
        storage.removeAll(keepingCapacity: true)
        calibrations.removeAll(keepingCapacity: true)
        deferred.removeAll(keepingCapacity: true)
        guard groups.isEmpty == false else { return (matchers, recordedCalibrations) }

        let deferredCount = groups.reduce(0) { $0 + $1.matchers.count }
        let everyArgumentHasOneMatcher =
            matchers.count + deferredCount == argumentCount
            && groups.allSatisfy { $0.matchers.count == 1 }
        if everyArgumentHasOneMatcher {
            // Positional matching: put each deferred matcher back at the
            // argument it describes.
            for group in groups where group.position <= matchers.count {
                matchers.insert(contentsOf: group.matchers, at: group.position)
            }
        } else {
            // Mixed literals: keep matchers paired with their calibrations so
            // placeholder bytes can locate each deferred matcher's argument.
            for group in groups {
                matchers.append(contentsOf: group.matchers)
            }
        }
        for group in groups {
            recordedCalibrations.append(contentsOf: group.calibrations)
        }
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

    /// Records a calibration for a closure matcher whose placeholder cannot
    /// be abstracted into a calibration value. It keeps matchers and
    /// calibrations paired and locates function-typed arguments.
    @inline(never)
    static func appendFunctionCalibration() {
        activeRecording?.appendCalibration(FunctionPlaceholderCalibration())
        RuntimeStubFactory.scrubArgumentRegisters()
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
    static func takeRecording(
        argumentCount: Int? = nil
    ) -> (
        matchers: [ParameterMatcher],
        calibrations: [RuntimeArgumentCalibration]
    ) {
        activeRecording?.takeRecording(argumentCount: argumentCount) ?? ([], [])
    }

    /// Evaluates a deferred argument and files the matchers it forms under
    /// `position`, so they pair with that argument instead of trailing the
    /// eagerly evaluated ones.
    static func evaluatingDeferredArgument<Value, Failure: Error>(
        at position: Int,
        _ argument: () throws(Failure) -> Value
    ) throws(Failure) -> Value {
        guard let parent = activeRecording else { return try argument() }
        let nested = MatcherRecording()
        let value: Value
        do {
            value = try $activeRecording.withValue(nested) {
                do {
                    return try argument()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure("[TestDoubles] Task-local matcher storage unexpectedly threw \(error).")
        }
        let recording = nested.takeRecording()
        parent.appendDeferred(
            at: position,
            matchers: recording.matchers,
            calibrations: recording.calibrations
        )
        return value
    }

    /// Asynchronous variant of ``evaluatingDeferredArgument(at:_:)``.
    static func evaluatingDeferredArgument<Value, Failure: Error>(
        at position: Int,
        isolation: isolated (any Actor)? = #isolation,
        _ argument: () async throws(Failure) -> Value
    ) async throws(Failure) -> Value {
        guard let parent = activeRecording else { return try await argument() }
        let nested = MatcherRecording()
        let value: Value
        do {
            value = try await $activeRecording.withValue(nested) {
                do {
                    return try await argument()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure("[TestDoubles] Task-local matcher storage unexpectedly threw \(error).")
        }
        let recording = nested.takeRecording()
        parent.appendDeferred(
            at: position,
            matchers: recording.matchers,
            calibrations: recording.calibrations
        )
        return value
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

    /// The number of captured values.
    public var count: Int { withLock { storage.count } }

    /// Whether no value has been captured yet.
    public var isEmpty: Bool { withLock { storage.isEmpty } }

    /// The captured value at `index`, in call order.
    ///
    /// - Precondition: `index` is within `0 ..< count`. Reading a captor that
    ///   recorded fewer calls than the test expected traps the same way an
    ///   out-of-bounds `Array` subscript does; use ``count`` or ``values``
    ///   when the capture count is itself under test.
    public subscript(index: Int) -> Value {
        withLock { storage[index] }
    }

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

    /// Matches any closure argument, including a nonescaping one.
    ///
    /// Swift cannot bind the generic ``Match/any()->T`` to a nonescaping function
    /// parameter, so this overload supplies an escaping closure that converts
    /// to any effect, isolation, or `Sendable` variant of the parameter's
    /// function type. Recording never calls the placeholder; calling it
    /// terminates the process.
    ///
    /// ```swift
    /// stub.when { $0.map(Match.any(), transform: Match.any()) }
    /// ```
    @_disfavoredOverload
    public static func any<each Argument, Result>() -> @Sendable (repeat each Argument) -> Result {
        MatcherContext.append(AnyMatcher())
        let placeholder: @Sendable (repeat each Argument) -> Result = { (_: repeat each Argument) in
            fatalError(
                "[TestDoubles] A Match.any() closure placeholder was called. Recording "
                    + "passes it to the requirement only to describe the call."
            )
        }
        MatcherContext.appendFunctionCalibration()
        return placeholder
    }

    /// Matches any argument of type `T`, using `placeholder` while recording the call.
    ///
    /// Use this overload when ``Match/any()->T`` cannot safely synthesize a value, such as
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
                + "Pass a valid value with \(fallback), or supply a "
                + "factory with Match.Placeholders.withFactory (scoped to the current "
                + "task) or Match.Placeholders.register (process-wide)."
        )
    }
    return placeholder
}
