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
        let bytes = withUnsafeBytes(of: placeholder) { Array($0) }
        let value: Any = copy placeholder
        lock.lock()
        calibrations.append(
            RuntimeArgumentCalibration(
                type: T.self,
                bytes: bytes,
                promotedBytes: { expectedType in
                    optionalPromotionBytes(
                        value,
                        baseType: T.self,
                        expectedType: expectedType
                    )
                }
            )
        )
        lock.unlock()
    }

    func currentCalibrations() -> [RuntimeArgumentCalibration] {
        lock.lock()
        defer { lock.unlock() }
        return calibrations
    }

    func takeMatchers() -> [ParameterMatcher] {
        lock.lock()
        defer { lock.unlock() }
        let matchers = storage
        storage.removeAll(keepingCapacity: true)
        calibrations.removeAll(keepingCapacity: true)
        return matchers
    }
}

private func optionalPromotionBytes<T>(
    _ value: Any,
    baseType: T.Type,
    expectedType: Any.Type
) -> [UInt8]? {
    var optionalLayers: [any RuntimeOptionalType.Type] = []
    var wrappedType = expectedType
    while ObjectIdentifier(wrappedType) != ObjectIdentifier(baseType),
        let optional = wrappedType as? any RuntimeOptionalType.Type
    {
        optionalLayers.append(optional)
        wrappedType = optional.runtimeWrappedType
    }
    guard optionalLayers.isEmpty == false,
        ObjectIdentifier(wrappedType) == ObjectIdentifier(baseType)
    else {
        return nil
    }

    var promoted = value
    for optional in optionalLayers.reversed() {
        guard let injected = optional.injectRuntimeOptional(promoted) else {
            return nil
        }
        promoted = injected
    }
    return _openExistential(promoted, do: rawValueBytes)
}

private func rawValueBytes<T>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
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
}

/// Namespaces argument matchers, captures, and recording placeholders.
///
/// Every matcher returns the argument's own type so it can be written directly
/// inside a call-recording closure. Keeping the vocabulary under one namespace
/// makes available matchers discoverable through autocomplete without
/// occupying the module's global function namespace.
public enum Match {}

extension Match {
    /// Matches any argument of type `T`.
    ///
    /// This overload synthesizes a valid recording placeholder. For reference,
    /// existential, or other unsupported types, use ``Match/any(using:)``.
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

    /// Captures matching argument values for later inspection.
    public final class Capture<T> {
        private let lock = NSLock()
        private var storage: [T] = []

        /// All captured values, in call order.
        public var values: [T] { withLock { storage } }

        /// The first captured value.
        public var first: T? { withLock { storage.first } }

        /// The most recently captured value.
        public var last: T? { withLock { storage.last } }

        /// Creates an empty capture.
        public init() {}

        /// Returns a matcher placeholder that captures each matching argument.
        ///
        /// This overload synthesizes a valid recording placeholder. For reference,
        /// existential, or other unsupported types, use ``capture(using:)``.
        public func capture() -> T {
            MatcherContext.append(CaptureMatcher(capture: self))
            return MatcherContext.returning(
                synthesizedPlaceholder(
                    for: "Match.Capture.capture()",
                    fallback: "Match.Capture.capture(using:)"
                )
            )
        }

        /// Returns a matcher placeholder that captures each matching argument.
        ///
        /// Use this overload when ``capture()`` cannot safely synthesize a value,
        /// such as for reference or existential types. The placeholder is never captured.
        ///
        /// - Parameter placeholder: A valid value accepted by the stubbed requirement.
        public func capture(using placeholder: T) -> T {
            MatcherContext.append(CaptureMatcher(capture: self))
            return MatcherContext.returning(placeholder)
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
}

/// A capture uses a lock to serialize its storage. It can cross concurrency
/// domains only when its captured values can do so safely as well.
extension Match.Capture: @unchecked Sendable where T: Sendable {}

/// Synthesizes the recording placeholder a matcher returns at its call site,
/// preferring a suite-wide registered factory, or traps pointing at the
/// `using:` overload that accepts a caller-supplied value.
func synthesizedPlaceholder<T>(for api: String, fallback: String) -> T {
    if let registered = Match.Placeholders.make(T.self) {
        return registered
    }
    guard let placeholder = RuntimeStubFactory.makeRecordingPlaceholder(for: T.self) else {
        fatalError(
            "[TestDoubles] \(api) cannot safely synthesize a placeholder for \(T.self). "
                + "Pass a valid value with \(fallback), or register a suite-wide "
                + "factory with Match.Placeholders.register."
        )
    }
    return placeholder
}
