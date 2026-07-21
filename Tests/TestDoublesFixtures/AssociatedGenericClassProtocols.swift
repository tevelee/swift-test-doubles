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

public struct ExternalAssociatedValue<Value> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public enum ExternalAssociatedChoice<Value> {
    case value(Value)
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
