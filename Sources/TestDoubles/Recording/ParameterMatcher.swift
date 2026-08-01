protocol ParameterMatcher {
    /// Evaluates this matcher once and returns the capture mutations that may
    /// be committed if the whole matcher transaction succeeds.
    func prepareMatch(value: Any) -> PreparedMatcherTransaction?
    var diagnosticDescription: String { get }

    /// `true` when this matcher accepts every value at its argument position.
    /// Used to prove an earlier registration shadows a later one. A universal
    /// matcher at a position accepts a superset of anything registered after
    /// it there.
    var acceptsAnyValue: Bool { get }

    /// A stable identity for matchers whose accepted set is fully determined
    /// by hashable semantic data. Two matchers with equal, non-`nil`
    /// identities provably accept the same set. `nil` when acceptance depends
    /// on an opaque predicate, a captured reference, or unhashable data, so
    /// equality cannot be proven soundly.
    var acceptanceIdentity: MatcherAcceptanceIdentity? { get }
}

struct MatcherAcceptanceIdentity: Hashable {
    let matcherType: ObjectIdentifier
    let values: [AnyHashable]

    init(_ matcherType: Any.Type, values: [AnyHashable]) {
        self.matcherType = ObjectIdentifier(matcherType)
        self.values = values
    }
}

/// A matcher whose accepted set has a sound hash key. The schema separates
/// matcher families and generic value types; the value is identical exactly
/// when `prepareMatch` would accept the invocation argument.
protocol ExactMatchIndexable {
    var exactMatchIndexSchema: ObjectIdentifier { get }
    var exactMatchIndexValue: AnyHashable { get }
    func exactMatchIndexValue(for value: Any) -> AnyHashable?
}

/// The side effects prepared by a successful matcher evaluation.
///
/// Predicates and projections run while this value is built. Committing it
/// only appends already-type-checked values to captors, so a recorder may make
/// matching decisions outside its policy lock and apply their effects at the
/// invocation's linearization point without re-running user code.
struct PreparedMatcherTransaction {
    private enum Captures {
        case none
        case one(() -> Void)
        case many([() -> Void])
    }

    private var captures: Captures

    static var matched: PreparedMatcherTransaction {
        PreparedMatcherTransaction(captures: .none)
    }

    init(captureMutation: @escaping () -> Void) {
        captures = .one(captureMutation)
    }

    private init(captures: Captures) {
        self.captures = captures
    }

    mutating func append(_ transaction: PreparedMatcherTransaction) {
        switch (captures, transaction.captures) {
            case (_, .none):
                break
            case (.none, let captures):
                self.captures = captures
            case (.one(let first), .one(let second)):
                captures = .many([first, second])
            case (.one(let first), .many(let additional)):
                captures = .many([first] + additional)
            case (.many(var existing), .one(let mutation)):
                existing.append(mutation)
                captures = .many(existing)
            case (.many(var existing), .many(let additional)):
                existing.append(contentsOf: additional)
                captures = .many(existing)
        }
    }

    func commitCaptures() {
        switch captures {
            case .none:
                break
            case .one(let mutation):
                mutation()
            case .many(let mutations):
                mutations.forEach { $0() }
        }
    }
}

extension ParameterMatcher {
    func matches(value: Any) -> Bool { prepareMatch(value: value) != nil }
    var diagnosticDescription: String { String(describing: Self.self) }
    var acceptsAnyValue: Bool { false }
    var acceptanceIdentity: MatcherAcceptanceIdentity? { nil }
}

struct AnyMatcher: ParameterMatcher {
    func prepareMatch(value: Any) -> PreparedMatcherTransaction? { .matched }
    var diagnosticDescription: String { "Match.any()" }
    var acceptsAnyValue: Bool { true }
}

struct CaptureMatcher<T>: ParameterMatcher {
    let capture: Match.Capture<T>

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? T else { return nil }
        return PreparedMatcherTransaction {
            capture.append(value)
        }
    }

    var diagnosticDescription: String { "capture(\(T.self))" }

    // A bare capture accepts every value of its argument's type, so it
    // shadows anything registered after it at that position.
    var acceptsAnyValue: Bool { true }
}

struct PredicateMatcher<Value>: ParameterMatcher {
    let description: String
    let predicate: @Sendable (Value) -> Bool

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Value else { return nil }
        return predicate(value) ? .matched : nil
    }

    var diagnosticDescription: String { "Match.matching(\(description))" }
}

func literalMatcher(for value: Any) -> ParameterMatcher {
    func equalityMatcher<Value: Equatable>(for value: Value) -> ParameterMatcher {
        EqualMatcher(expected: value)
    }

    if type(of: value) is AnyObject.Type {
        return IdenticalMatcher(expected: value as AnyObject)
    }
    if let matcher = optionalReferenceMatcher(for: value) {
        return matcher
    }
    if let value = value as? any Equatable {
        return _openExistential(value, do: equalityMatcher)
    }
    if let value = value as? Any.Type {
        return MetatypeMatcher(expected: value)
    }
    preconditionFailure(
        "[TestDoubles] Cannot record the literal value of type \(type(of: value)) because it has no "
            + "generic equality. Use Match expressions for every argument in this call, such as "
            + "Match.any(using:), Match.identical(to:), or "
            + "Match.matching(using:description:where:)."
    )
}

private protocol OptionalRuntimeType {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalRuntimeType {
    fileprivate static var wrappedType: Any.Type { Wrapped.self }
}

private func optionalReferenceMatcher(for value: Any) -> ParameterMatcher? {
    let optionalType = type(of: value)
    guard nestedOptionalReferenceType(optionalType) else { return nil }
    return OptionalReferenceMatcher(
        optionalType: optionalType,
        expected: optionalReferenceValue(value, of: optionalType)
    )
}

/// Reports whether `type` is one or more optional layers around a reference.
///
/// `Optional<Reference>` does not itself conform to `Equatable`, so literal
/// recording needs the same identity semantics as a direct reference. Keep
/// peeling the declared optional shape rather than inspecting only the outer
/// layer: `Reference??` must distinguish `.none`, `.some(.none)`, and a
/// concrete object just as ordinary Swift equality would if it were available.
private func nestedOptionalReferenceType(_ type: Any.Type) -> Bool {
    var currentType = type
    var hasOptionalLayer = false
    while let optional = currentType as? any OptionalRuntimeType.Type {
        hasOptionalLayer = true
        currentType = optional.wrappedType
    }
    return hasOptionalLayer && currentType is AnyObject.Type
}

private enum OptionalReferenceValue {
    case none(atLayer: Int)
    case object(AnyObject)
}

private func optionalReferenceValue(
    _ value: Any,
    of optionalType: Any.Type
) -> OptionalReferenceValue {
    var currentValue = value
    var currentType = optionalType
    var layer = 0
    while let optional = currentType as? any OptionalRuntimeType.Type {
        guard let unwrapped = unwrapOptional(currentValue) else {
            return .none(atLayer: layer)
        }
        currentValue = unwrapped
        currentType = optional.wrappedType
        layer += 1
    }
    // `nestedOptionalReferenceType(_:)` proves the terminal declared type is
    // a reference. Keeping that proof next to the conversion avoids bridging
    // arbitrary value types through `AnyObject`.
    return .object(currentValue as AnyObject)
}

struct EqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        (value as? Value) == expected ? .matched : nil
    }
    var diagnosticDescription: String { "Match.equal(\(String(describing: expected)))" }
    var acceptanceIdentity: MatcherAcceptanceIdentity? {
        guard let expected = expected as? any Hashable else { return nil }
        return MatcherAcceptanceIdentity(Self.self, values: [AnyHashable(expected)])
    }
}

extension EqualMatcher: ExactMatchIndexable where Value: Hashable {
    var exactMatchIndexSchema: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }

    var exactMatchIndexValue: AnyHashable {
        AnyHashable(expected)
    }

    func exactMatchIndexValue(for value: Any) -> AnyHashable? {
        guard let value = value as? Value else { return nil }
        return AnyHashable(value)
    }
}

struct NotEqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        (value as? Value) != expected ? .matched : nil
    }
    var diagnosticDescription: String { "Match.notEqual(\(String(describing: expected)))" }
    var acceptanceIdentity: MatcherAcceptanceIdentity? {
        guard let expected = expected as? any Hashable else { return nil }
        return MatcherAcceptanceIdentity(Self.self, values: [AnyHashable(expected)])
    }
}

struct IdenticalMatcher: ParameterMatcher {
    let expected: AnyObject

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard type(of: value) is AnyObject.Type else { return nil }
        return (value as AnyObject) === expected ? .matched : nil
    }
    var diagnosticDescription: String { "Match.identical(to: \(expected))" }
}

private struct OptionalReferenceMatcher: ParameterMatcher {
    let optionalType: Any.Type
    let expected: OptionalReferenceValue

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard ObjectIdentifier(type(of: value)) == ObjectIdentifier(optionalType) else {
            return nil
        }
        let actual = optionalReferenceValue(value, of: optionalType)
        switch (expected, actual) {
            case (.none(let expectedLayer), .none(let actualLayer)):
                return expectedLayer == actualLayer ? .matched : nil
            case (.object(let expected), .object(let actual)):
                return expected === actual ? .matched : nil
            case (.none, .object), (.object, .none):
                return nil
        }
    }

    var diagnosticDescription: String {
        switch expected {
            case .none:
                return "literal(nil)"
            case .object(let expected):
                return "literal(\(expected))"
        }
    }
}

struct MetatypeMatcher: ParameterMatcher {
    let expected: Any.Type

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Any.Type else { return nil }
        return value == expected ? .matched : nil
    }

    var diagnosticDescription: String { "literal(\(expected))" }
}

struct ComparisonMatcher<Value: Comparable>: ParameterMatcher {
    enum Relation: String {
        case greaterThan
        case atLeast
        case lessThan
        case atMost
    }

    let relation: Relation
    let bound: Value

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Value else { return nil }
        let matches: Bool
        switch relation {
            case .greaterThan: matches = value > bound
            case .atLeast: matches = value >= bound
            case .lessThan: matches = value < bound
            case .atMost: matches = value <= bound
        }
        return matches ? .matched : nil
    }

    var diagnosticDescription: String { "\(relation.rawValue)(\(String(describing: bound)))" }
    var acceptanceIdentity: MatcherAcceptanceIdentity? {
        guard let bound = bound as? any Hashable else { return nil }
        return MatcherAcceptanceIdentity(
            Self.self,
            values: [AnyHashable(relation.rawValue), AnyHashable(bound)]
        )
    }
}

struct RangeMatcher<Bound: Comparable>: ParameterMatcher {
    let contains: @Sendable (Bound) -> Bool
    let boundsDescription: String

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Bound else { return nil }
        return contains(value) ? .matched : nil
    }

    var diagnosticDescription: String { "Match.inRange(\(boundsDescription))" }
    // The closure is the semantic range; its display text is only a
    // diagnostic and cannot prove two ranges identical.
    var acceptanceIdentity: MatcherAcceptanceIdentity? { nil }
}

struct ApproximateMatcher<Value: BinaryFloatingPoint>: ParameterMatcher {
    let expected: Value
    let absoluteTolerance: Value
    let relativeTolerance: Value

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Value else { return nil }
        if value == expected { return .matched }
        guard value.isFinite, expected.isFinite else { return nil }
        let difference = Swift.abs(value - expected)
        let scale = Swift.max(Swift.abs(value), Swift.abs(expected))
        let tolerance = Swift.max(absoluteTolerance, relativeTolerance * scale)
        return difference <= tolerance ? .matched : nil
    }

    var diagnosticDescription: String {
        "Match.approximately(\(expected), absoluteTolerance: "
            + "\(absoluteTolerance), relativeTolerance: \(relativeTolerance))"
    }

    var acceptanceIdentity: MatcherAcceptanceIdentity? {
        MatcherAcceptanceIdentity(
            Self.self,
            values: [
                AnyHashable(expected),
                AnyHashable(absoluteTolerance),
                AnyHashable(relativeTolerance)
            ]
        )
    }
}

struct NilMatcher: ParameterMatcher {
    let expectsNil: Bool

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        valueIsNil(value) == expectsNil ? .matched : nil
    }
    var diagnosticDescription: String { expectsNil ? "Match.isNil()" : "Match.notNil()" }
    var acceptanceIdentity: MatcherAcceptanceIdentity? {
        MatcherAcceptanceIdentity(Self.self, values: [AnyHashable(expectsNil)])
    }
}

/// Matches a non-`nil` optional whose wrapped value satisfies every nested matcher.
struct SomeMatcher: ParameterMatcher {
    let wrapped: [ParameterMatcher]

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let unwrapped = unwrapOptional(value) else { return nil }
        return prepareAll(wrapped, value: unwrapped)
    }

    var diagnosticDescription: String {
        "Match.some(\(wrapped.map(\.diagnosticDescription).joined(separator: ", ")))"
    }
}

/// Applies source-level matcher expressions to the elements of a variadic
/// argument. Swift lowers the whole argument as one Array, but the recording
/// closure still evaluates one `Match` expression per written element.
struct VariadicElementsMatcher: ParameterMatcher {
    let elements: [ParameterMatcher]

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        let reflected = Mirror(reflecting: value)
        guard reflected.displayStyle == .collection else { return nil }
        let values = reflected.children.map(\.value)
        guard values.count == elements.count else { return nil }

        var combined = PreparedMatcherTransaction.matched
        for (matcher, value) in zip(elements, values) {
            guard let transaction = matcher.prepareMatch(value: value) else {
                return nil
            }
            combined.append(transaction)
        }
        return combined
    }

    var diagnosticDescription: String {
        "variadic(\(elements.map(\.diagnosticDescription).joined(separator: ", ")))"
    }
}

/// Combines nested matchers with boolean logic while remaining a single
/// positional matcher, so composed expressions align with one argument.
struct CompositeMatcher: ParameterMatcher {
    enum Mode {
        case all
        case any
        case not
    }

    let mode: Mode
    let matchers: [ParameterMatcher]

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        switch mode {
            case .all:
                return prepareAll(matchers, value: value)
            case .any:
                for matcher in matchers {
                    if let transaction = matcher.prepareMatch(value: value) {
                        return transaction
                    }
                }
                return nil
            case .not:
                return prepareAll(matchers, value: value) == nil ? .matched : nil
        }
    }

    var diagnosticDescription: String {
        let inner = matchers.map(\.diagnosticDescription).joined(separator: ", ")
        switch mode {
            case .all: return "Match.allOf(\(inner))"
            case .any: return "Match.anyOf(\(inner))"
            case .not: return "Match.not(\(inner))"
        }
    }
}

/// Matches a value of `Value` accepted by a predicate, rendering a caller-supplied
/// diagnostic description verbatim (unlike ``PredicateMatcher``, which wraps it).
struct TypedPredicateMatcher<Value>: ParameterMatcher {
    let diagnosticDescription: String
    let predicate: (Value) -> Bool

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Value else { return nil }
        return predicate(value) ? .matched : nil
    }
}

/// Projects a value to a derived value, then matches nested matchers against the
/// projection. `project` returns `nil` when the value is not of the expected type.
struct ProjectionMatcher: ParameterMatcher {
    let label: String
    let matchers: [ParameterMatcher]
    let project: (Any) -> Any?

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let projected = project(value) else { return nil }
        return prepareAll(matchers, value: projected)
    }

    var diagnosticDescription: String {
        "\(label)(\(matchers.map(\.diagnosticDescription).joined(separator: ", ")))"
    }
}

/// Extracts the associated values of one enum case and applies one nested
/// matcher to each value. A `nil` extraction rejects values of every other case.
struct EnumCaseMatcher: ParameterMatcher {
    let label: String
    let matchers: [ParameterMatcher]
    let extract: (Any) -> [Any]?

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let associatedValues = extract(value),
            associatedValues.count == matchers.count
        else {
            return nil
        }

        var combined = PreparedMatcherTransaction.matched
        for (matcher, associatedValue) in zip(matchers, associatedValues) {
            guard let transaction = matcher.prepareMatch(value: associatedValue) else {
                return nil
            }
            combined.append(transaction)
        }
        return combined
    }

    var diagnosticDescription: String {
        "\(label)(\(matchers.map(\.diagnosticDescription).joined(separator: ", ")))"
    }
}

/// Evaluates a conjunction once, discarding every prepared capture if any
/// matcher rejects the value.
private func prepareAll(
    _ matchers: [ParameterMatcher],
    value: Any
) -> PreparedMatcherTransaction? {
    var combined = PreparedMatcherTransaction.matched
    for matcher in matchers {
        guard let transaction = matcher.prepareMatch(value: value) else { return nil }
        combined.append(transaction)
    }
    return combined
}

/// Reports whether a type-erased value is an optional carrying no value.
///
/// A non-optional value is never `nil`; an optional reports its own presence.
func valueIsNil(_ value: Any) -> Bool {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return false }
    return mirror.children.isEmpty
}

/// Returns the wrapped value of a present optional, or `nil` for an absent
/// optional. A non-optional value is returned unchanged.
func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
}
