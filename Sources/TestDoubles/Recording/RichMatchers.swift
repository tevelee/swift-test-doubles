import Foundation

// Composable and value-oriented argument matchers built on the same recording
// mechanism as ``Match/any()``, ``Match/equal(_:)``, and
// ``Match/matching(description:where:)``.
//
// Every function here appends exactly one ``ParameterMatcher`` to the active
// recording and returns a value of the argument's own type, so matchers stay
// positional: use matcher functions for every argument of a `when`/`verify`
// call or none, never a mix. Combinators fold the matchers their nested
// expressions record into a single composite through ``MatcherContext``'s
// nested-capture support, which is why negation and conjunction are spelled as
// `Match.not(Match.equal(3))` and `Match.allOf(...)` rather than with `!` and `&&`: the
// expressions are typed as the argument, not as a matcher wrapper.

/// The escape hatch named when a collection placeholder cannot be synthesized.
private let collectionPlaceholderFallback = "Match.matching(using:description:where:)"

extension Match {
    // MARK: - Logical combinators

    /// Matches an argument the nested matcher rejects.
    ///
    /// - Parameter matcher: A single nested matcher expression, for example
    ///   `Match.not(Match.equal(0))` or `Match.not(Match.anyOf(1, 2, 3))`.
    public static func not<T>(_ matcher: @autoclosure () -> T) -> T {
        let (placeholder, matchers) = MatcherContext.captureNested { matcher() }
        MatcherContext.append(CompositeMatcher(mode: .not, matchers: matchers))
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument accepted by both nested matchers.
    public static func allOf<T>(_ first: @autoclosure () -> T, _ second: @autoclosure () -> T) -> T {
        let (placeholder, a) = MatcherContext.captureNested(first)
        let b = MatcherContext.captureNested(second).matchers
        MatcherContext.append(CompositeMatcher(mode: .all, matchers: a + b))
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument accepted by all three nested matchers.
    public static func allOf<T>(
        _ first: @autoclosure () -> T,
        _ second: @autoclosure () -> T,
        _ third: @autoclosure () -> T
    ) -> T {
        let (placeholder, a) = MatcherContext.captureNested(first)
        let b = MatcherContext.captureNested(second).matchers
        let c = MatcherContext.captureNested(third).matchers
        MatcherContext.append(CompositeMatcher(mode: .all, matchers: a + b + c))
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument accepted by all four nested matchers.
    public static func allOf<T>(
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
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument accepted by either nested matcher.
    public static func anyOf<T>(_ first: @autoclosure () -> T, _ second: @autoclosure () -> T) -> T {
        let (placeholder, a) = MatcherContext.captureNested(first)
        let b = MatcherContext.captureNested(second).matchers
        MatcherContext.append(CompositeMatcher(mode: .any, matchers: a + b))
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument accepted by any of the three nested matchers.
    public static func anyOf<T>(
        _ first: @autoclosure () -> T,
        _ second: @autoclosure () -> T,
        _ third: @autoclosure () -> T
    ) -> T {
        let (placeholder, a) = MatcherContext.captureNested(first)
        let b = MatcherContext.captureNested(second).matchers
        let c = MatcherContext.captureNested(third).matchers
        MatcherContext.append(CompositeMatcher(mode: .any, matchers: a + b + c))
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument accepted by any of the four nested matchers.
    public static func anyOf<T>(
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
        return MatcherContext.returning(placeholder)
    }

    /// Matches an argument equal to any of the listed values.
    ///
    /// A shorthand for `Match.anyOf(Match.equal(a), Match.equal(b), …)`.
    public static func oneOf<T: Equatable>(_ values: T...) -> T {
        precondition(values.isEmpty == false, "[TestDoubles] oneOf requires at least one value.")
        MatcherContext.append(
            CompositeMatcher(mode: .any, matchers: values.map { EqualMatcher(expected: $0) })
        )
        return MatcherContext.returning(values[0])
    }

    // MARK: - Equality and identity

    /// Matches an argument not equal to `value`.
    public static func notEqual<T: Equatable>(_ value: T) -> T {
        MatcherContext.append(NotEqualMatcher(expected: value))
        return MatcherContext.returning(value)
    }

    /// Matches an argument that is the same object instance as `object` (`===`).
    public static func identical<T: AnyObject>(to object: T) -> T {
        MatcherContext.append(IdenticalMatcher(expected: object))
        return MatcherContext.returning(object)
    }

    // MARK: - Comparison

    /// Matches an argument greater than `value`.
    public static func greaterThan<T: Comparable>(_ value: T) -> T {
        MatcherContext.append(ComparisonMatcher(relation: .greaterThan, bound: value))
        return MatcherContext.returning(value)
    }

    /// Matches an argument greater than or equal to `value`.
    public static func atLeast<T: Comparable>(_ value: T) -> T {
        MatcherContext.append(ComparisonMatcher(relation: .atLeast, bound: value))
        return MatcherContext.returning(value)
    }

    /// Matches an argument less than `value`.
    public static func lessThan<T: Comparable>(_ value: T) -> T {
        MatcherContext.append(ComparisonMatcher(relation: .lessThan, bound: value))
        return MatcherContext.returning(value)
    }

    /// Matches an argument less than or equal to `value`.
    public static func atMost<T: Comparable>(_ value: T) -> T {
        MatcherContext.append(ComparisonMatcher(relation: .atMost, bound: value))
        return MatcherContext.returning(value)
    }

    /// Matches an argument contained in `range`.
    public static func inRange<Bound: Comparable & Sendable>(_ range: Range<Bound>) -> Bound {
        MatcherContext.append(
            RangeMatcher<Bound>(contains: { range.contains($0) }, boundsDescription: "\(range)")
        )
        return MatcherContext.returning(range.lowerBound)
    }

    /// Matches an argument contained in `range`.
    public static func inRange<Bound: Comparable & Sendable>(_ range: ClosedRange<Bound>) -> Bound {
        MatcherContext.append(
            RangeMatcher<Bound>(contains: { range.contains($0) }, boundsDescription: "\(range)")
        )
        return MatcherContext.returning(range.lowerBound)
    }

    /// Matches a floating-point argument within absolute or relative
    /// tolerance of `value`.
    ///
    /// A value matches when its difference is no larger than the greater of
    /// `absoluteTolerance` and `relativeTolerance` times the larger
    /// magnitude. Both tolerances must be finite and nonnegative.
    public static func approximately<Value: BinaryFloatingPoint>(
        _ value: Value,
        absoluteTolerance: Value = 0,
        relativeTolerance: Value = 0
    ) -> Value {
        precondition(
            absoluteTolerance.isFinite && absoluteTolerance >= 0,
            "[TestDoubles] absoluteTolerance must be finite and nonnegative."
        )
        precondition(
            relativeTolerance.isFinite && relativeTolerance >= 0,
            "[TestDoubles] relativeTolerance must be finite and nonnegative."
        )
        MatcherContext.append(
            ApproximateMatcher(
                expected: value,
                absoluteTolerance: absoluteTolerance,
                relativeTolerance: relativeTolerance
            )
        )
        return MatcherContext.returning(value)
    }

    // MARK: - Projection

    /// Matches a value whose property at `keyPath` equals `expected`.
    ///
    /// This overload synthesizes the root placeholder used while recording.
    /// Use ``property(using:_:equalTo:)`` for reference, existential, or other
    /// root types that require an explicit placeholder.
    public static func property<Root, Value: Equatable>(
        _ keyPath: KeyPath<Root, Value>,
        equalTo expected: Value
    ) -> Root {
        appendPropertyMatcher(keyPath, equalTo: expected)
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "Match.property(_:equalTo:)",
                fallback: "Match.property(using:_:equalTo:)"
            )
        )
    }

    /// Matches a value whose property at `keyPath` equals `expected`, using
    /// `placeholder` only while recording the call.
    public static func property<Root, Value: Equatable>(
        using placeholder: Root,
        _ keyPath: KeyPath<Root, Value>,
        equalTo expected: Value
    ) -> Root {
        appendPropertyMatcher(keyPath, equalTo: expected)
        return MatcherContext.returning(placeholder)
    }

    private static func appendPropertyMatcher<Root, Value: Equatable>(
        _ keyPath: KeyPath<Root, Value>,
        equalTo expected: Value
    ) {
        MatcherContext.append(
            ProjectionMatcher(
                label: "property(\(keyPath))",
                matchers: [EqualMatcher(expected: expected)]
            ) { value in
                guard let root = value as? Root else { return nil }
                return root[keyPath: keyPath]
            }
        )
    }

    // MARK: - Enum cases

    /// Matches an enum case and applies `matcher` to its associated value.
    ///
    /// Return the associated value from `extract` for the named case and `nil`
    /// for every other case. The matcher expression can use any existing
    /// `Match` API, including captures and logical combinators.
    public static func enumCase<Enum, Associated>(
        _ name: String,
        extracting extract: @escaping @Sendable (Enum) -> Associated?,
        matching matcher: @autoclosure () -> Associated
    ) -> Enum {
        let (_, matchers) = MatcherContext.captureNested { matcher() }
        appendEnumCaseMatcher(name, associatedValueCount: 1, matchers: matchers) { value in
            guard let root = value as? Enum, let associated = extract(root) else {
                return nil
            }
            return [associated]
        }
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "Match.enumCase(_:extracting:matching:)",
                fallback: "Match.enumCase(using:_:extracting:matching:)"
            )
        )
    }

    /// Matches an enum case and applies one matcher to each associated value.
    ///
    /// Return both associated values from `extract` for the named case and
    /// `nil` for every other case.
    public static func enumCase<Enum, First, Second>(
        _ name: String,
        extracting extract: @escaping @Sendable (Enum) -> (First, Second)?,
        matching first: @autoclosure () -> First,
        _ second: @autoclosure () -> Second
    ) -> Enum {
        let (_, firstMatchers) = MatcherContext.captureNested { first() }
        let (_, secondMatchers) = MatcherContext.captureNested { second() }
        appendEnumCaseMatcher(
            name,
            associatedValueCount: 2,
            matchers: firstMatchers + secondMatchers
        ) { value in
            guard let root = value as? Enum, let associated = extract(root) else {
                return nil
            }
            return [associated.0, associated.1]
        }
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "Match.enumCase(_:extracting:matching:_:)",
                fallback: "Match.enumCase(using:_:extracting:matching:_:)"
            ))
    }

    /// Matches an enum case and its associated value, using `placeholder` only
    /// while recording the call.
    public static func enumCase<Enum, Associated>(
        using placeholder: Enum,
        _ name: String,
        extracting extract: @escaping @Sendable (Enum) -> Associated?,
        matching matcher: @autoclosure () -> Associated
    ) -> Enum {
        let (_, matchers) = MatcherContext.captureNested { matcher() }
        appendEnumCaseMatcher(name, associatedValueCount: 1, matchers: matchers) { value in
            guard let root = value as? Enum, let associated = extract(root) else {
                return nil
            }
            return [associated]
        }
        return MatcherContext.returning(placeholder)
    }

    /// Matches an enum case and its two associated values, using `placeholder`
    /// only while recording the call.
    public static func enumCase<Enum, First, Second>(
        using placeholder: Enum,
        _ name: String,
        extracting extract: @escaping @Sendable (Enum) -> (First, Second)?,
        matching first: @autoclosure () -> First,
        _ second: @autoclosure () -> Second
    ) -> Enum {
        let (_, firstMatchers) = MatcherContext.captureNested { first() }
        let (_, secondMatchers) = MatcherContext.captureNested { second() }
        appendEnumCaseMatcher(
            name,
            associatedValueCount: 2,
            matchers: firstMatchers + secondMatchers
        ) { value in
            guard let root = value as? Enum, let associated = extract(root) else {
                return nil
            }
            return [associated.0, associated.1]
        }
        return MatcherContext.returning(placeholder)
    }

    private static func appendEnumCaseMatcher(
        _ name: String,
        associatedValueCount: Int,
        matchers: [ParameterMatcher],
        extract: @escaping (Any) -> [Any]?
    ) {
        precondition(
            matchers.count == associatedValueCount,
            "[TestDoubles] enumCase requires exactly one Match expression "
                + "for every associated value."
        )
        MatcherContext.append(
            EnumCaseMatcher(
                label: "enumCase(\(name))",
                matchers: matchers,
                extract: extract
            )
        )
    }

    // MARK: - Optionals

    /// Matches a `nil` optional argument.
    public static func isNil<Wrapped>() -> Wrapped? {
        MatcherContext.append(NilMatcher(expectsNil: true))
        return MatcherContext.returning(nil as Wrapped?)
    }

    /// Matches a non-`nil` optional argument, regardless of the wrapped value.
    public static func notNil<Wrapped>() -> Wrapped? {
        MatcherContext.append(NilMatcher(expectsNil: false))
        return MatcherContext.returning(nil as Wrapped?)
    }

    /// Matches a non-`nil` optional whose wrapped value satisfies `matcher`.
    ///
    /// - Parameter matcher: A nested matcher applied to the unwrapped value, for
    ///   example `Match.some(Match.greaterThan(0))`.
    public static func some<Wrapped>(_ matcher: @autoclosure () -> Wrapped) -> Wrapped? {
        let (placeholder, matchers) = MatcherContext.captureNested { matcher() }
        MatcherContext.append(SomeMatcher(wrapped: matchers))
        return MatcherContext.returning(Optional.some(placeholder))
    }

    // MARK: - Collections

    /// Matches an empty collection argument.
    public static func isEmpty<C: Collection>() -> C {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "isEmpty()") { $0.isEmpty }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "isEmpty()",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a non-empty collection argument.
    public static func nonEmpty<C: Collection>() -> C {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "nonEmpty()") { $0.isEmpty == false }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "nonEmpty()",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument whose element count equals `count`.
    public static func hasCount<C: Collection>(_ count: Int) -> C {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "hasCount(\(count))") { $0.count == count }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "hasCount(_:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument whose element count satisfies `matcher`.
    ///
    /// - Parameter matcher: A nested matcher applied to the collection's `count`,
    ///   for example `Match.hasCount(matching: Match.greaterThan(2))`.
    public static func hasCount<C: Collection>(matching matcher: @autoclosure () -> Int) -> C {
        let (_, matchers) = MatcherContext.captureNested { matcher() }
        MatcherContext.append(
            ProjectionMatcher(label: "hasCount", matchers: matchers) { value in
                guard let collection = value as? C else { return nil }
                return collection.count
            }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "hasCount(matching:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument that contains `element`.
    public static func contains<C: Collection>(_ element: C.Element) -> C where C.Element: Equatable & Sendable {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "contains(\(String(describing: element)))") {
                $0.contains(element)
            }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "contains(_:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument that contains an element accepted by `predicate`.
    public static func contains<C: Collection>(where predicate: @escaping @Sendable (C.Element) -> Bool) -> C {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "contains(where:)") {
                $0.contains(where: predicate)
            }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "contains(where:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument that contains every listed element.
    public static func containsAll<C: Collection>(_ elements: C.Element...) -> C where C.Element: Equatable & Sendable {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "containsAll(\(descriptionOf(elements)))") {
                collection in elements.allSatisfy { collection.contains($0) }
            }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "containsAll(_:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument whose leading elements equal `prefix`.
    public static func startsWith<C: Collection>(_ prefix: C.Element...) -> C where C.Element: Equatable & Sendable {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "startsWith(\(descriptionOf(prefix)))") {
                $0.starts(with: prefix)
            }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "startsWith(_:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    /// Matches a collection argument whose trailing elements equal `suffix`.
    public static func endsWith<C: Collection>(_ suffix: C.Element...) -> C where C.Element: Equatable & Sendable {
        MatcherContext.append(
            TypedPredicateMatcher<C>(diagnosticDescription: "endsWith(\(descriptionOf(suffix)))") {
                $0.suffix(suffix.count).elementsEqual(suffix)
            }
        )
        return MatcherContext.returning(
            synthesizedPlaceholder(
                for: "endsWith(_:)",
                fallback: collectionPlaceholderFallback
            )
        )
    }

    // MARK: - Strings

    /// Matches a string argument that begins with `prefix`.
    public static func hasPrefix(_ prefix: String) -> String {
        MatcherContext.append(
            TypedPredicateMatcher<String>(diagnosticDescription: "hasPrefix(\"\(prefix)\")") {
                $0.hasPrefix(prefix)
            }
        )
        return MatcherContext.returning("")
    }

    /// Matches a string argument that ends with `suffix`.
    public static func hasSuffix(_ suffix: String) -> String {
        MatcherContext.append(
            TypedPredicateMatcher<String>(diagnosticDescription: "hasSuffix(\"\(suffix)\")") {
                $0.hasSuffix(suffix)
            }
        )
        return MatcherContext.returning("")
    }

    /// Matches a string argument that contains `substring`.
    public static func containsSubstring(_ substring: String) -> String {
        MatcherContext.append(
            TypedPredicateMatcher<String>(
                diagnosticDescription: "containsSubstring(\"\(substring)\")"
            ) { $0.range(of: substring) != nil }
        )
        return MatcherContext.returning("")
    }

    /// Matches a string argument equal to `value`, ignoring case.
    public static func equalsIgnoringCase(_ value: String) -> String {
        MatcherContext.append(
            TypedPredicateMatcher<String>(diagnosticDescription: "equalsIgnoringCase(\"\(value)\")") {
                $0.lowercased() == value.lowercased()
            }
        )
        return MatcherContext.returning("")
    }

    /// Matches a string argument that contains a match for the regular expression `pattern`.
    public static func matchesRegex(_ pattern: String) -> String {
        MatcherContext.append(
            TypedPredicateMatcher<String>(diagnosticDescription: "matchesRegex(\"\(pattern)\")") {
                $0.range(of: pattern, options: .regularExpression) != nil
            }
        )
        return MatcherContext.returning("")
    }

    /// Matches a string argument that contains a match for a native Swift
    /// regular expression.
    ///
    /// The regex may have any typed output, including capture tuples. Matching
    /// uses the regex's native semantic level and options.
    public static func matchesRegex<Output>(_ regex: Regex<Output>) -> String {
        MatcherContext.append(
            TypedPredicateMatcher<String>(
                diagnosticDescription: "matchesRegex(\(String(describing: regex)))"
            ) {
                $0.firstMatch(of: regex) != nil
            }
        )
        return MatcherContext.returning("")
    }

    private static func descriptionOf<Element>(_ values: [Element]) -> String {
        values.map { String(describing: $0) }.joined(separator: ", ")
    }
}
