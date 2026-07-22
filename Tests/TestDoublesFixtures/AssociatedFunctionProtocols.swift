public protocol ExternalAssociatedFunctionProbe<Element> {
    associatedtype Element

    func apply(_ transform: @escaping (Element) -> String) -> String
    func makeTransform(from seed: Int) -> (Int) -> Element
    func applyOptional(
        _ transform: @escaping ([Element]?) -> String,
    ) -> String
}

public struct RealExternalAssociatedFunctionProbe:
    ExternalAssociatedFunctionProbe
{
    public init() {}

    public func apply(_ transform: @escaping (Int) -> String) -> String {
        transform(21)
    }

    public func makeTransform(from seed: Int) -> (Int) -> Int {
        { seed + $0 }
    }

    public func applyOptional(
        _ transform: @escaping ([Int]?) -> String,
    ) -> String {
        transform([21])
    }
}

public protocol ExternalNonescapingAssociatedFunctionProbe<Element> {
    associatedtype Element

    func apply(_ transform: (Element) -> String) -> String
}

public struct RealExternalNonescapingAssociatedFunctionProbe:
    ExternalNonescapingAssociatedFunctionProbe
{
    public init() {}

    public func apply(_ transform: (Int) -> String) -> String {
        transform(21)
    }
}

public protocol ExternalAsyncAssociatedFunctionProbe<Element> {
    associatedtype Element

    func apply(_ transform: @escaping (Element) async -> String) async -> String
}

public struct RealExternalAsyncAssociatedFunctionProbe:
    ExternalAsyncAssociatedFunctionProbe
{
    public init() {}

    public func apply(
        _ transform: @escaping (Int) async -> String,
    ) async -> String {
        await transform(21)
    }
}

public protocol ExternalThrowingAssociatedFunctionProbe<Element> {
    associatedtype Element

    func apply(_ transform: @escaping (Element) throws -> String) throws -> String
}

public struct RealExternalThrowingAssociatedFunctionProbe:
    ExternalThrowingAssociatedFunctionProbe
{
    public init() {}

    public func apply(
        _ transform: @escaping (Int) throws -> String,
    ) throws -> String {
        try transform(21)
    }
}

public protocol ExternalInoutAssociatedFunctionProbe<Element> {
    associatedtype Element

    func apply(_ transform: @escaping (inout Element) -> String) -> String
}

public struct RealExternalInoutAssociatedFunctionProbe:
    ExternalInoutAssociatedFunctionProbe
{
    public init() {}

    public func apply(_ transform: @escaping (inout Int) -> String) -> String {
        var value = 21
        return transform(&value)
    }
}

public enum ExternalAssociatedFunctionError: Error {
    case failed
}

public protocol ExternalTypedThrowingAssociatedFunctionProbe<Failure> {
    associatedtype Failure: Error

    func apply(
        _ transform: @escaping (Int) throws(Failure) -> String,
    ) throws(Failure) -> String
}

public struct RealExternalTypedThrowingAssociatedFunctionProbe:
    ExternalTypedThrowingAssociatedFunctionProbe
{
    public init() {}

    public func apply(
        _ transform: @escaping (Int) throws(ExternalAssociatedFunctionError) -> String,
    ) throws(ExternalAssociatedFunctionError) -> String {
        try transform(21)
    }
}
