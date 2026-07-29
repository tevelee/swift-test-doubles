/// A reusable, strongly typed argument matcher.
///
/// Conform a value type in a test-support target or matcher package, then pass
/// an instance to ``Match/custom(_:)``:
///
/// ```swift
/// struct MultipleOf: CustomMatcher {
///     let divisor: Int
///
///     var diagnosticDescription: String { "multipleOf(\(divisor))" }
///     func matches(_ value: Int) -> Bool { value.isMultiple(of: divisor) }
/// }
/// ```
public protocol CustomMatcher<Value>: Sendable {
    /// The argument type accepted by this matcher.
    associatedtype Value

    /// A concise description rendered in mismatch diagnostics.
    var diagnosticDescription: String { get }

    /// Returns whether `value` is accepted.
    func matches(_ value: Value) -> Bool
}

extension CustomMatcher {
    /// Uses the conforming type name when no custom diagnostic is needed.
    public var diagnosticDescription: String {
        String(describing: Self.self)
    }
}

extension Match {
    /// Matches an argument with a reusable ``CustomMatcher``.
    ///
    /// This overload synthesizes the recording placeholder. Use
    /// ``custom(using:_:)`` when `M.Value` needs an explicit placeholder.
    public static func custom<M: CustomMatcher>(_ matcher: M) -> M.Value {
        MatcherContext.append(CustomMatcherAdapter(matcher: matcher))
        return synthesizedPlaceholder(
            for: "Match.custom(_:)",
            fallback: "Match.custom(using:_:)"
        )
    }

    /// Matches an argument with a reusable ``CustomMatcher``, using
    /// `placeholder` only while recording the call.
    public static func custom<M: CustomMatcher>(
        using placeholder: M.Value,
        _ matcher: M
    ) -> M.Value {
        MatcherContext.append(CustomMatcherAdapter(matcher: matcher))
        return placeholder
    }
}

private struct CustomMatcherAdapter<M: CustomMatcher>: ParameterMatcher {
    let matcher: M

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? M.Value else { return nil }
        return matcher.matches(value) ? .matched : nil
    }

    var diagnosticDescription: String {
        "Match.custom(\(matcher.diagnosticDescription))"
    }
}
