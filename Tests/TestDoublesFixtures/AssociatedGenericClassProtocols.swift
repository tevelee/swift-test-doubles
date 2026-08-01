public final class ExternalAssociatedBox<Value> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public final class ExternalAssociatedPair<First, Second> {
    public let first: First
    public let second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}

public final class ExternalAssociatedTriple<First, Second, Third> {
    public let first: First
    public let second: Second
    public let third: Third

    public init(_ first: First, _ second: Second, _ third: Third) {
        self.first = first
        self.second = second
        self.third = third
    }
}

public final class ExternalAlternativeAssociatedBox<Value> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public final class ExternalConstrainedAssociatedBox<Value: Hashable> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

/// Constrains both parameters, so resolving it exercises two witness-table
/// key arguments in the same call (four key arguments total).
public struct ExternalBothParametersConstrainedPair<First: Hashable, Second: Hashable> {
    public let first: First
    public let second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}

/// Constrains only its second parameter, so resolving it exercises the
/// `q_` (depth 0, index 1) generic-parameter mangling, not just the `x`
/// (depth 0, index 0) shortcut a single-parameter constrained type would.
public struct ExternalSecondParameterConstrainedPair<First, Second: Hashable> {
    public let first: First
    public let second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}

public struct ExternalAssociatedValue<Value> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public struct ExternalAssociatedTripleValue<First, Second, Third> {
    public let first: First
    public let second: Second
    public let third: Third

    public init(_ first: First, _ second: Second, _ third: Third) {
        self.first = first
        self.second = second
        self.third = third
    }
}

public enum ExternalAssociatedChoice<Value> {
    case value(Value)
}

public protocol ExternalWideGenericNominalAssociatedProbe<Element> {
    associatedtype Element

    func transform(
        _ value: ExternalAssociatedTriple<Element, String, Int>
    ) -> ExternalAssociatedTriple<Element, String, Int>
    func transform(
        _ value: ExternalAssociatedTripleValue<Element, String, Int>
    ) -> ExternalAssociatedTripleValue<Element, String, Int>
}

public struct RealExternalWideGenericNominalAssociatedProbe:
    ExternalWideGenericNominalAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ExternalAssociatedTriple<Int, String, Int>
    ) -> ExternalAssociatedTriple<Int, String, Int> {
        value
    }

    public func transform(
        _ value: ExternalAssociatedTripleValue<Int, String, Int>
    ) -> ExternalAssociatedTripleValue<Int, String, Int> {
        value
    }
}

public protocol ExternalGenericClassAssociatedProbe<Element> {
    associatedtype Element

    func transform(
        box value: ExternalAssociatedBox<Element>
    ) -> ExternalAssociatedBox<Element>
    func transform(
        pair value: ExternalAssociatedPair<[Element]?, String>
    ) -> ExternalAssociatedPair<[Element]?, String>
    func transform(
        optional value: ExternalAssociatedBox<Element>?
    ) -> ExternalAssociatedBox<Element>?
    func transform(
        collection value: [ExternalAssociatedBox<Element>]
    ) -> [ExternalAssociatedBox<Element>]
    func transform(
        nestedClass value: ExternalAssociatedPair<
            ExternalAssociatedBox<Element>,
            String
        >
    ) -> ExternalAssociatedPair<ExternalAssociatedBox<Element>, String>
}

public struct RealExternalGenericClassAssociatedProbe:
    ExternalGenericClassAssociatedProbe
{
    public init() {}

    public func transform(
        box value: ExternalAssociatedBox<Int>
    ) -> ExternalAssociatedBox<Int> {
        value
    }

    public func transform(
        pair value: ExternalAssociatedPair<[Int]?, String>
    ) -> ExternalAssociatedPair<[Int]?, String> {
        value
    }

    public func transform(
        optional value: ExternalAssociatedBox<Int>?
    ) -> ExternalAssociatedBox<Int>? {
        value
    }

    public func transform(
        collection value: [ExternalAssociatedBox<Int>]
    ) -> [ExternalAssociatedBox<Int>] {
        value
    }

    public func transform(
        nestedClass value: ExternalAssociatedPair<
            ExternalAssociatedBox<Int>,
            String
        >
    ) -> ExternalAssociatedPair<ExternalAssociatedBox<Int>, String> {
        value
    }
}

public protocol ExternalGenericStructAssociatedProbe<Element> {
    associatedtype Element

    func transform(
        _ value: ExternalAssociatedValue<Element>
    ) -> ExternalAssociatedValue<Element>
}

public struct RealExternalGenericStructAssociatedProbe:
    ExternalGenericStructAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ExternalAssociatedValue<Int>
    ) -> ExternalAssociatedValue<Int> {
        value
    }
}

public protocol ExternalGenericParentAssociatedProbe<Element> {
    associatedtype Element

    func transform(
        _ value: ExternalGenericParent<Element>.Payload
    ) -> ExternalGenericParent<Element>.Payload
}

public struct RealExternalGenericParentAssociatedProbe:
    ExternalGenericParentAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ExternalGenericParent<Int>.Payload
    ) -> ExternalGenericParent<Int>.Payload {
        value
    }
}

public protocol ExternalConstrainedGenericParentAssociatedProbe<Element> {
    associatedtype Element: ExternalFirstGenericConstraint

    func transform(
        _ value: ConstrainedGenericParent<Element>.Payload
    ) -> ConstrainedGenericParent<Element>.Payload
}

public struct RealExternalConstrainedGenericParentAssociatedProbe:
    ExternalConstrainedGenericParentAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ConstrainedGenericParent<String>.Payload
    ) -> ConstrainedGenericParent<String>.Payload {
        value
    }
}

public protocol ExternalConstrainedGenericStructAssociatedProbe<Element> {
    associatedtype Element

    func transform(
        _ value: ExternalSecondParameterConstrainedPair<Element, String>
    ) -> ExternalSecondParameterConstrainedPair<Element, String>
}

public struct RealExternalConstrainedGenericStructAssociatedProbe:
    ExternalConstrainedGenericStructAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ExternalSecondParameterConstrainedPair<Int, String>
    ) -> ExternalSecondParameterConstrainedPair<Int, String> {
        value
    }
}

public protocol ExternalGenericEnumAssociatedProbe<Element> {
    associatedtype Element

    func transform(
        _ value: ExternalAssociatedChoice<Element>
    ) -> ExternalAssociatedChoice<Element>
}

public struct RealExternalGenericEnumAssociatedProbe:
    ExternalGenericEnumAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ExternalAssociatedChoice<Int>
    ) -> ExternalAssociatedChoice<Int> {
        value
    }
}

public protocol ExternalConstrainedGenericClassAssociatedProbe<Element> {
    associatedtype Element: Hashable

    func transform(
        _ value: ExternalConstrainedAssociatedBox<Element>
    ) -> ExternalConstrainedAssociatedBox<Element>
}

public struct RealExternalConstrainedGenericClassAssociatedProbe:
    ExternalConstrainedGenericClassAssociatedProbe
{
    public init() {}

    public func transform(
        _ value: ExternalConstrainedAssociatedBox<Int>
    ) -> ExternalConstrainedAssociatedBox<Int> {
        value
    }
}
