protocol ParameterMatcher {
    func matches(value: Any) -> Bool
    func commit(value: Any)
    var specificity: Int { get }
    var diagnosticDescription: String { get }
}

extension ParameterMatcher {
    func commit(value: Any) {}
    var diagnosticDescription: String { String(describing: Self.self) }
}

struct AnyMatcher: ParameterMatcher {
    func matches(value: Any) -> Bool { true }
    var specificity: Int { 0 }
    var diagnosticDescription: String { "any()" }
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

    var specificity: Int { 0 }
    var diagnosticDescription: String { "capture(\(T.self))" }
}

struct PredicateMatcher<Value>: ParameterMatcher {
    let description: String
    let predicate: @Sendable (Value) -> Bool

    func matches(value: Any) -> Bool {
        guard let value = value as? Value else { return false }
        return predicate(value)
    }

    var specificity: Int { 1 }
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

    var specificity: Int { 2 }
    var diagnosticDescription: String { "literal(\(description))" }
}

struct EqualMatcher<Value: Equatable>: ParameterMatcher {
    let expected: Value

    func matches(value: Any) -> Bool { (value as? Value) == expected }
    var specificity: Int { 3 }
    var diagnosticDescription: String { "equal(\(String(describing: expected)))" }
}
