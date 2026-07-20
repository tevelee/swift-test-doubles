import Foundation

// Composable and value-oriented argument matchers built on the same recording
// mechanism as ``any()``, ``equal(_:)``, and ``matching(description:where:)``.
//
// Every function here appends exactly one ``ParameterMatcher`` to the active
// recording and returns a value of the argument's own type, so matchers stay
// positional: use matcher functions for every argument of a `when`/`verify`
// call or none, never a mix. Combinators fold the matchers their nested
// expressions record into a single composite through ``MatcherContext``'s
// nested-capture support, which is why negation and conjunction are spelled as
// `not(equal(3))` and `allOf(...)` rather than with `!` and `&&`: the
// expressions are typed as the argument, not as a matcher wrapper.

// MARK: - Logical combinators

/// Matches an argument the nested matcher rejects.
///
/// - Parameter matcher: A single nested matcher expression, for example
///   `not(equal(0))` or `not(anyOf(1, 2, 3))`.
public func not<T>(_ matcher: @autoclosure () -> T) -> T {
    let (placeholder, matchers) = MatcherContext.captureNested { matcher() }
    MatcherContext.append(CompositeMatcher(mode: .not, matchers: matchers))
    return placeholder
}

/// Matches an argument accepted by both nested matchers.
public func allOf<T>(_ first: @autoclosure () -> T, _ second: @autoclosure () -> T) -> T {
    let (placeholder, a) = MatcherContext.captureNested(first)
    let b = MatcherContext.captureNested(second).matchers
    MatcherContext.append(CompositeMatcher(mode: .all, matchers: a + b))
    return placeholder
}

/// Matches an argument accepted by all three nested matchers.
public func allOf<T>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ third: @autoclosure () -> T
) -> T {
    let (placeholder, a) = MatcherContext.captureNested(first)
    let b = MatcherContext.captureNested(second).matchers
    let c = MatcherContext.captureNested(third).matchers
    MatcherContext.append(CompositeMatcher(mode: .all, matchers: a + b + c))
    return placeholder
}

/// Matches an argument accepted by all four nested matchers.
public func allOf<T>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ third: @autoclosure () -> T,
    _ fourth: @autoclosure () -> T
) -> T {
    let (placeholder, a) = MatcherContext.captureNested(first)
    let b = MatcherContext.captureNested(second).matchers
    let c = MatcherContext.captureNested(third).matchers
    let d = MatcherContext.captureNested(fourth).matchers
    MatcherContext.append(CompositeMatcher(mode: .all, matchers: a + b + c + d))
    return placeholder
}

/// Matches an argument accepted by either nested matcher.
public func anyOf<T>(_ first: @autoclosure () -> T, _ second: @autoclosure () -> T) -> T {
    let (placeholder, a) = MatcherContext.captureNested(first)
    let b = MatcherContext.captureNested(second).matchers
    MatcherContext.append(CompositeMatcher(mode: .any, matchers: a + b))
    return placeholder
}

/// Matches an argument accepted by any of the three nested matchers.
public func anyOf<T>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ third: @autoclosure () -> T
) -> T {
    let (placeholder, a) = MatcherContext.captureNested(first)
    let b = MatcherContext.captureNested(second).matchers
    let c = MatcherContext.captureNested(third).matchers
    MatcherContext.append(CompositeMatcher(mode: .any, matchers: a + b + c))
    return placeholder
}

/// Matches an argument accepted by any of the four nested matchers.
public func anyOf<T>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ third: @autoclosure () -> T,
    _ fourth: @autoclosure () -> T
) -> T {
    let (placeholder, a) = MatcherContext.captureNested(first)
    let b = MatcherContext.captureNested(second).matchers
    let c = MatcherContext.captureNested(third).matchers
    let d = MatcherContext.captureNested(fourth).matchers
    MatcherContext.append(CompositeMatcher(mode: .any, matchers: a + b + c + d))
    return placeholder
}

/// Matches an argument equal to any of the listed values.
///
/// A shorthand for `anyOf(equal(a), equal(b), …)`.
public func oneOf<T: Equatable>(_ values: T...) -> T {
    precondition(values.isEmpty == false, "[TestDoubles] oneOf requires at least one value.")
    MatcherContext.append(
        CompositeMatcher(mode: .any, matchers: values.map { EqualMatcher(expected: $0) })
    )
    return values[0]
}

// MARK: - Equality and identity

/// Matches an argument not equal to `value`.
public func notEqual<T: Equatable>(_ value: T) -> T {
    MatcherContext.append(NotEqualMatcher(expected: value))
    return value
}

/// Matches an argument that is the same object instance as `object` (`===`).
public func identical<T: AnyObject>(to object: T) -> T {
    MatcherContext.append(IdenticalMatcher(expected: object))
    return object
}

// MARK: - Comparison

/// Matches an argument greater than `value`.
public func greaterThan<T: Comparable>(_ value: T) -> T {
    MatcherContext.append(ComparisonMatcher(relation: .greaterThan, bound: value))
    return value
}

/// Matches an argument greater than or equal to `value`.
public func atLeast<T: Comparable>(_ value: T) -> T {
    MatcherContext.append(ComparisonMatcher(relation: .atLeast, bound: value))
    return value
}

/// Matches an argument less than `value`.
public func lessThan<T: Comparable>(_ value: T) -> T {
    MatcherContext.append(ComparisonMatcher(relation: .lessThan, bound: value))
    return value
}

/// Matches an argument less than or equal to `value`.
public func atMost<T: Comparable>(_ value: T) -> T {
    MatcherContext.append(ComparisonMatcher(relation: .atMost, bound: value))
    return value
}

/// Matches an argument contained in `range`.
public func inRange<Bound: Comparable & Sendable>(_ range: Range<Bound>) -> Bound {
    MatcherContext.append(
        RangeMatcher<Bound>(contains: { range.contains($0) }, boundsDescription: "\(range)")
    )
    return range.lowerBound
}

/// Matches an argument contained in `range`.
public func inRange<Bound: Comparable & Sendable>(_ range: ClosedRange<Bound>) -> Bound {
    MatcherContext.append(
        RangeMatcher<Bound>(contains: { range.contains($0) }, boundsDescription: "\(range)")
    )
    return range.lowerBound
}

// MARK: - Optionals

/// Matches a `nil` optional argument.
public func isNil<Wrapped>() -> Wrapped? {
    MatcherContext.append(NilMatcher(expectsNil: true))
    return nil
}

/// Matches a non-`nil` optional argument, regardless of the wrapped value.
public func notNil<Wrapped>() -> Wrapped? {
    MatcherContext.append(NilMatcher(expectsNil: false))
    return nil
}

/// Matches a non-`nil` optional whose wrapped value satisfies `matcher`.
///
/// - Parameter matcher: A nested matcher applied to the unwrapped value, for
///   example `some(greaterThan(0))`.
public func some<Wrapped>(_ matcher: @autoclosure () -> Wrapped) -> Wrapped? {
    let (placeholder, matchers) = MatcherContext.captureNested { matcher() }
    MatcherContext.append(SomeMatcher(wrapped: matchers))
    return placeholder
}

// MARK: - Collections

/// The escape hatch named when a collection placeholder cannot be synthesized.
private let collectionPlaceholderFallback = "matching(using:description:where:)"

/// Matches an empty collection argument.
public func isEmpty<C: Collection>() -> C {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "isEmpty()") { $0.isEmpty }
    )
    return synthesizedPlaceholder(for: "isEmpty()", fallback: collectionPlaceholderFallback)
}

/// Matches a non-empty collection argument.
public func nonEmpty<C: Collection>() -> C {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "nonEmpty()") { $0.isEmpty == false }
    )
    return synthesizedPlaceholder(for: "nonEmpty()", fallback: collectionPlaceholderFallback)
}

/// Matches a collection argument whose element count equals `count`.
public func hasCount<C: Collection>(_ count: Int) -> C {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "hasCount(\(count))") { $0.count == count }
    )
    return synthesizedPlaceholder(for: "hasCount(_:)", fallback: collectionPlaceholderFallback)
}

/// Matches a collection argument whose element count satisfies `matcher`.
///
/// - Parameter matcher: A nested matcher applied to the collection's `count`,
///   for example `hasCount(matching: greaterThan(2))`.
public func hasCount<C: Collection>(matching matcher: @autoclosure () -> Int) -> C {
    let (_, matchers) = MatcherContext.captureNested { matcher() }
    MatcherContext.append(
        ProjectionMatcher(label: "hasCount", matchers: matchers) { value in
            guard let collection = value as? C else { return nil }
            return collection.count
        }
    )
    return synthesizedPlaceholder(
        for: "hasCount(matching:)",
        fallback: collectionPlaceholderFallback
    )
}

/// Matches a collection argument that contains `element`.
public func contains<C: Collection>(_ element: C.Element) -> C where C.Element: Equatable & Sendable {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "contains(\(String(describing: element)))") {
            $0.contains(element)
        }
    )
    return synthesizedPlaceholder(for: "contains(_:)", fallback: collectionPlaceholderFallback)
}

/// Matches a collection argument that contains an element accepted by `predicate`.
public func contains<C: Collection>(where predicate: @escaping @Sendable (C.Element) -> Bool) -> C {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "contains(where:)") {
            $0.contains(where: predicate)
        }
    )
    return synthesizedPlaceholder(for: "contains(where:)", fallback: collectionPlaceholderFallback)
}

/// Matches a collection argument that contains every listed element.
public func containsAll<C: Collection>(_ elements: C.Element...) -> C where C.Element: Equatable & Sendable {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "containsAll(\(descriptionOf(elements)))") {
            collection in elements.allSatisfy { collection.contains($0) }
        }
    )
    return synthesizedPlaceholder(for: "containsAll(_:)", fallback: collectionPlaceholderFallback)
}

/// Matches a collection argument whose leading elements equal `prefix`.
public func startsWith<C: Collection>(_ prefix: C.Element...) -> C where C.Element: Equatable & Sendable {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "startsWith(\(descriptionOf(prefix)))") {
            $0.starts(with: prefix)
        }
    )
    return synthesizedPlaceholder(for: "startsWith(_:)", fallback: collectionPlaceholderFallback)
}

/// Matches a collection argument whose trailing elements equal `suffix`.
public func endsWith<C: Collection>(_ suffix: C.Element...) -> C where C.Element: Equatable & Sendable {
    MatcherContext.append(
        TypedPredicateMatcher<C>(diagnosticDescription: "endsWith(\(descriptionOf(suffix)))") {
            $0.suffix(suffix.count).elementsEqual(suffix)
        }
    )
    return synthesizedPlaceholder(for: "endsWith(_:)", fallback: collectionPlaceholderFallback)
}

// MARK: - Strings

/// Matches a string argument that begins with `prefix`.
public func hasPrefix(_ prefix: String) -> String {
    MatcherContext.append(
        TypedPredicateMatcher<String>(diagnosticDescription: "hasPrefix(\"\(prefix)\")") {
            $0.hasPrefix(prefix)
        }
    )
    return ""
}

/// Matches a string argument that ends with `suffix`.
public func hasSuffix(_ suffix: String) -> String {
    MatcherContext.append(
        TypedPredicateMatcher<String>(diagnosticDescription: "hasSuffix(\"\(suffix)\")") {
            $0.hasSuffix(suffix)
        }
    )
    return ""
}

/// Matches a string argument that contains `substring`.
public func containsSubstring(_ substring: String) -> String {
    MatcherContext.append(
        TypedPredicateMatcher<String>(
            diagnosticDescription: "containsSubstring(\"\(substring)\")"
        ) { $0.range(of: substring) != nil }
    )
    return ""
}

/// Matches a string argument equal to `value`, ignoring case.
public func equalsIgnoringCase(_ value: String) -> String {
    MatcherContext.append(
        TypedPredicateMatcher<String>(diagnosticDescription: "equalsIgnoringCase(\"\(value)\")") {
            $0.lowercased() == value.lowercased()
        }
    )
    return ""
}

/// Matches a string argument that contains a match for the regular expression `pattern`.
public func matchesRegex(_ pattern: String) -> String {
    MatcherContext.append(
        TypedPredicateMatcher<String>(diagnosticDescription: "matchesRegex(\"\(pattern)\")") {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
    )
    return ""
}

private func descriptionOf<Element>(_ values: [Element]) -> String {
    values.map { String(describing: $0) }.joined(separator: ", ")
}
