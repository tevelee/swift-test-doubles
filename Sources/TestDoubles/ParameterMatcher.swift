// MARK: - ParameterMatcher

/// Protocol for argument matchers used internally by when and verify calls.
///
/// The built-in matchers — any(), ``equal(_:)``, ``any(where:)``, and ``ArgumentCaptor`` —
/// cover the common public extension points. Conform to this protocol when
/// extending the library or adding a public helper that appends a matcher into
/// the matcher context.
///
/// ```swift
/// struct NonEmptyMatcher: ParameterMatcher {
///     func matches(value: Any) -> Bool {
///         (value as? String).map { !$0.isEmpty } ?? false
///     }
///     var specificity: Int { 1 }
/// }
/// ```
public protocol ParameterMatcher {
    /// Returns `true` if this matcher accepts `value`.
    func matches(value: Any) -> Bool
    /// Relative priority when multiple stubs match the same call.
    /// Higher specificity wins. `any()` = 0, predicate = 1, description = 2, equal = 3.
    var specificity: Int { get }
    /// Human-readable matcher spelling used in failure diagnostics.
    var diagnosticDescription: String { get }
}

public extension ParameterMatcher {
    var diagnosticDescription: String { String(describing: Self.self) }
}

// MARK: - Built-in implementations

struct AnyMatcher: ParameterMatcher {
    func matches(value: Any) -> Bool { true }
    var specificity: Int { 0 }
    var diagnosticDescription: String { "any()" }
}

struct CaptureMatcher<T>: ParameterMatcher {
    let captor: ArgumentCaptor<T>
    func matches(value: Any) -> Bool {
        if let v = value as? T { captor.values.append(v) }
        return true
    }
    var specificity: Int { 0 }
    var diagnosticDescription: String { "capture(\(T.self))" }
}

struct PredicateMatcher<V>: ParameterMatcher {
    let predicate: (V) -> Bool
    func matches(value: Any) -> Bool {
        guard let v = value as? V else { return false }
        return predicate(v)
    }
    var specificity: Int { 1 }
    var diagnosticDescription: String { "any(\(V.self), where:)" }
}

struct TypedMatcher<V>: ParameterMatcher {
    let matcher: Matcher<V>
    func matches(value: Any) -> Bool {
        guard let v = value as? V else { return false }
        return matcher.matches(v)
    }
    var specificity: Int { 1 }
    var diagnosticDescription: String { "matching(\(matcher.description))" }
}

struct DescriptionMatcher: ParameterMatcher {
    let desc: String
    init(value: Any) { self.desc = String(describing: value) }
    func matches(value: Any) -> Bool { String(describing: value) == desc }
    var specificity: Int { 2 }
    var diagnosticDescription: String { "equal(\(desc))" }
}

struct EqualMatcher<V: Equatable>: ParameterMatcher {
    let expected: V
    func matches(value: Any) -> Bool { (value as? V) == expected }
    var specificity: Int { 3 }
    var diagnosticDescription: String { "equal(\(String(describing: expected)))" }
}
