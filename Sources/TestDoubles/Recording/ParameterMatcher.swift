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
    /// by their description (value matchers like `equal`/`inRange`). Two
    /// matchers with equal, non-`nil` identities provably accept the same
    /// set. `nil` when acceptance depends on an opaque predicate, a captured
    /// reference, or composition, so equality cannot be proven soundly.
    var acceptanceIdentity: String? { get }
}

/// The side effects prepared by a successful matcher evaluation.
///
/// Predicates and projections run while this value is built. Committing it
/// only appends already-type-checked values to captors, so a recorder may make
/// matching decisions outside its policy lock and apply their effects at the
/// invocation's linearization point without re-running user code.
struct PreparedMatcherTransaction {
    private let captureMutations: [() -> Void]

    static var matched: PreparedMatcherTransaction {
        PreparedMatcherTransaction(captureMutations: [])
    }

    init(captureMutation: @escaping () -> Void) {
        captureMutations = [captureMutation]
    }

    private init(captureMutations: [() -> Void]) {
        self.captureMutations = captureMutations
    }

    static func combining(_ transactions: [PreparedMatcherTransaction]) -> Self {
        PreparedMatcherTransaction(
            captureMutations: transactions.flatMap(\.captureMutations)
        )
    }

    func commitCaptures() {
        captureMutations.forEach { $0() }
    }
}

extension ParameterMatcher {
    func matches(value: Any) -> Bool { prepareMatch(value: value) != nil }
    var diagnosticDescription: String { String(describing: Self.self) }
    var acceptsAnyValue: Bool { false }
    var acceptanceIdentity: String? { nil }
}

struct AnyMatcher: ParameterMatcher {
    func prepareMatch(value: Any) -> PreparedMatcherTransaction? { .matched }
    var diagnosticDescription: String { "any()" }
    var acceptsAnyValue: Bool { true }
}

struct CaptureMatcher<T>: ParameterMatcher {
    let captor: ArgumentCaptor<T>

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? T else { return nil }
        return PreparedMatcherTransaction {
            captor.append(value)
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

    var diagnosticDescription: String { "matching(\(description))" }
}

struct DescriptionMatcher: ParameterMatcher {
    let description: String

    init(value: Any) {
        description = String(describing: value)
    }

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        String(describing: value) == description ? .matched : nil
    }

    var diagnosticDescription: String { "literal(\(description))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct EqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        (value as? Value) == expected ? .matched : nil
    }
    var diagnosticDescription: String { "equal(\(String(describing: expected)))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct NotEqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        (value as? Value) != expected ? .matched : nil
    }
    var diagnosticDescription: String { "notEqual(\(String(describing: expected)))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct IdenticalMatcher: ParameterMatcher {
    let expected: AnyObject

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        (value as AnyObject) === expected ? .matched : nil
    }
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
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct RangeMatcher<Bound: Comparable>: ParameterMatcher {
    let contains: @Sendable (Bound) -> Bool
    let boundsDescription: String

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let value = value as? Bound else { return nil }
        return contains(value) ? .matched : nil
    }

    var diagnosticDescription: String { "inRange(\(boundsDescription))" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

struct NilMatcher: ParameterMatcher {
    let expectsNil: Bool

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        valueIsNil(value) == expectsNil ? .matched : nil
    }
    var diagnosticDescription: String { expectsNil ? "isNil()" : "notNil()" }
    var acceptanceIdentity: String? { diagnosticDescription }
}

/// Matches a non-`nil` optional whose wrapped value satisfies every nested matcher.
struct SomeMatcher: ParameterMatcher {
    let wrapped: [ParameterMatcher]

    func prepareMatch(value: Any) -> PreparedMatcherTransaction? {
        guard let unwrapped = unwrapOptional(value) else { return nil }
        return prepareAll(wrapped, value: unwrapped)
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

/// Evaluates a conjunction once, discarding every prepared capture if any
/// matcher rejects the value.
private func prepareAll(
    _ matchers: [ParameterMatcher],
    value: Any
) -> PreparedMatcherTransaction? {
    var transactions: [PreparedMatcherTransaction] = []
    transactions.reserveCapacity(matchers.count)
    for matcher in matchers {
        guard let transaction = matcher.prepareMatch(value: value) else { return nil }
        transactions.append(transaction)
    }
    return .combining(transactions)
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
