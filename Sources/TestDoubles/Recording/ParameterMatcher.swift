protocol ParameterMatcher {
    func matches(value: Any) -> Bool
    func commit(value: Any)
    var diagnosticDescription: String { get }

    /// `true` when this matcher accepts every value at its argument position.
    /// Used to prove an earlier registration shadows a later one. A universal
    /// matcher at a position accepts a superset of anything registered after
    /// it there.
    var acceptsAnyValue: Bool { get }

    /// A stable identity for matchers whose accepted set is fully determined
    /// by their description (value matchers like `equal`/`inRange`). Two
    /// matchers with equal, non-`nil` identities provably accept the same
    /// set. `nil` when acceptance depends on an opaque predicate, a captured
    /// reference, or composition, so equality cannot be proven soundly.
    var acceptanceIdentity: String? { get }
}

extension ParameterMatcher {
    func commit(value: Any) {}
    var diagnosticDescription: String { String(describing: Self.self) }
    var acceptsAnyValue: Bool { false }
    var acceptanceIdentity: String? { nil }
}

struct AnyMatcher: ParameterMatcher {
    func matches(value: Any) -> Bool { true }
    var diagnosticDescription: String { "any()" }
    var acceptsAnyValue: Bool { true }
}

struct CaptureMatcher<T>: ParameterMatcher {
    let captor: ArgumentCaptor<T>

    func matches(value: Any) -> Bool {
        value is T
    }

    func commit(value: Any) {
        guard let value = value as? T else { return }
        captor.append(value)
    }

    var diagnosticDescription: String { "capture(\(T.self))" }

    // A bare capture accepts every value of its argument's type, so it
    // shadows anything registered after it at that position.
    var acceptsAnyValue: Bool { true }
}

struct PredicateMatcher<Value>: ParameterMatcher {
    let description: String
    let predicate: @Sendable (Value) -> Bool

    func matches(value: Any) -> Bool {
        guard let value = value as? Value else { return false }
        return predicate(value)
    }

    var diagnosticDescription: String { "matching(\(description))" }
}

struct DescriptionMatcher: ParameterMatcher {
    let description: String

    init(value: Any) {
        description = String(describing: value)
    }

    func matches(value: Any) -> Bool {
        String(describing: value) == description
    }

    var diagnosticDescription: String { "literal(\(description))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct EqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func matches(value: Any) -> Bool { (value as? Value) == expected }
    var diagnosticDescription: String { "equal(\(String(describing: expected)))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct NotEqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func matches(value: Any) -> Bool { (value as? Value) != expected }
    var diagnosticDescription: String { "notEqual(\(String(describing: expected)))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct IdenticalMatcher: ParameterMatcher {
    let expected: AnyObject

    func matches(value: Any) -> Bool { (value as AnyObject) === expected }
    var diagnosticDescription: String { "identical(to: \(expected))" }
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

    func matches(value: Any) -> Bool {
        guard let value = value as? Value else { return false }
        switch relation {
            case .greaterThan: return value > bound
            case .atLeast: return value >= bound
            case .lessThan: return value < bound
            case .atMost: return value <= bound
        }
    }

    var diagnosticDescription: String { "\(relation.rawValue)(\(String(describing: bound)))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct RangeMatcher<Bound: Comparable>: ParameterMatcher {
    let contains: @Sendable (Bound) -> Bool
    let boundsDescription: String

    func matches(value: Any) -> Bool {
        guard let value = value as? Bound else { return false }
        return contains(value)
    }

    var diagnosticDescription: String { "inRange(\(boundsDescription))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct NilMatcher: ParameterMatcher {
    let expectsNil: Bool

    func matches(value: Any) -> Bool { valueIsNil(value) == expectsNil }
    var diagnosticDescription: String { expectsNil ? "isNil()" : "notNil()" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

/// Matches a non-`nil` optional whose wrapped value satisfies every nested matcher.
struct SomeMatcher: ParameterMatcher {
    let wrapped: [ParameterMatcher]

    func matches(value: Any) -> Bool {
        guard let unwrapped = unwrapOptional(value) else { return false }
        return wrapped.allSatisfy { $0.matches(value: unwrapped) }
    }

    func commit(value: Any) {
        guard let unwrapped = unwrapOptional(value) else { return }
        wrapped.forEach { $0.commit(value: unwrapped) }
    }

    var diagnosticDescription: String {
        "some(\(wrapped.map(\.diagnosticDescription).joined(separator: ", ")))"
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

    func matches(value: Any) -> Bool {
        switch mode {
            case .all: return matchers.allSatisfy { $0.matches(value: value) }
            case .any: return matchers.contains { $0.matches(value: value) }
            case .not: return matchers.allSatisfy { $0.matches(value: value) } == false
        }
    }

    func commit(value: Any) {
        switch mode {
            case .all:
                matchers.forEach { $0.commit(value: value) }
            case .any:
                // Commit captures only for the first satisfied branch, mirroring
                // the first-match-wins selection used everywhere else.
                if let matched = matchers.first(where: { $0.matches(value: value) }) {
                    matched.commit(value: value)
                }
            case .not:
                break
        }
    }

    var diagnosticDescription: String {
        let inner = matchers.map(\.diagnosticDescription).joined(separator: ", ")
        switch mode {
            case .all: return "allOf(\(inner))"
            case .any: return "anyOf(\(inner))"
            case .not: return "not(\(inner))"
        }
    }
}

/// Matches a value of `Value` accepted by a predicate, rendering a caller-supplied
/// diagnostic description verbatim (unlike ``PredicateMatcher``, which wraps it).
struct TypedPredicateMatcher<Value>: ParameterMatcher {
    let diagnosticDescription: String
    let predicate: (Value) -> Bool

    func matches(value: Any) -> Bool {
        guard let value = value as? Value else { return false }
        return predicate(value)
    }
}

/// Projects a value to a derived value, then matches nested matchers against the
/// projection. `project` returns `nil` when the value is not of the expected type.
struct ProjectionMatcher: ParameterMatcher {
    let label: String
    let matchers: [ParameterMatcher]
    let project: (Any) -> Any?

    func matches(value: Any) -> Bool {
        guard let projected = project(value) else { return false }
        return matchers.allSatisfy { $0.matches(value: projected) }
    }

    func commit(value: Any) {
        guard let projected = project(value) else { return }
        matchers.forEach { $0.commit(value: projected) }
    }

    var diagnosticDescription: String {
        "\(label)(\(matchers.map(\.diagnosticDescription).joined(separator: ", ")))"
    }
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
