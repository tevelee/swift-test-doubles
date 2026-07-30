public final class ExternalAssociatedClassError<Value>: Error, @unchecked Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public final class ExternalAssociatedPairClassError<First, Second>:
    Error, @unchecked Sendable
{
    public let first: First
    public let second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}

public final class ExternalAssociatedTripleClassError<First, Second, Third>:
    Error, @unchecked Sendable
{
    public let first: First
    public let second: Second
    public let third: Third

    public init(_ first: First, _ second: Second, _ third: Third) {
        self.first = first
        self.second = second
        self.third = third
    }
}

public final class ExternalConstrainedAssociatedClassError<Value: Hashable>:
    Error, @unchecked Sendable
{
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public protocol ExternalAssociatedClassTypedErrorProbe<Element> {
    associatedtype Element

    func oneParameter(
        _ code: Int
    ) throws(ExternalAssociatedClassError<Element>) -> Int
    func twoParameters(
        _ code: Int
    ) throws(ExternalAssociatedPairClassError<Element, String>) -> String
    func nestedClass(
        _ code: Int
    ) throws(ExternalAssociatedPairClassError<
        ExternalAssociatedClassError<Element>,
        String
    >) -> Int
    func asynchronous(
        _ code: Int
    ) async throws(ExternalAssociatedClassError<Element>) -> String
}

public struct RealExternalAssociatedClassTypedErrorProbe:
    ExternalAssociatedClassTypedErrorProbe
{
    public init() {}

    public func oneParameter(
        _ code: Int
    ) throws(ExternalAssociatedClassError<Int>) -> Int {
        if code != 0 { throw ExternalAssociatedClassError(code) }
        return 10
    }

    public func twoParameters(
        _ code: Int
    ) throws(ExternalAssociatedPairClassError<Int, String>) -> String {
        if code != 0 {
            throw ExternalAssociatedPairClassError(code, "two")
        }
        return "two"
    }

    public func nestedClass(
        _ code: Int
    ) throws(ExternalAssociatedPairClassError<
        ExternalAssociatedClassError<Int>,
        String
    >) -> Int {
        if code != 0 {
            throw ExternalAssociatedPairClassError(
                ExternalAssociatedClassError(code),
                "nested"
            )
        }
        return 30
    }

    public func asynchronous(
        _ code: Int
    ) async throws(ExternalAssociatedClassError<Int>) -> String {
        if code != 0 { throw ExternalAssociatedClassError(code) }
        return "async"
    }
}

public protocol ExternalWideAssociatedClassTypedErrorProbe<Element> {
    associatedtype Element

    func load(
        _ code: Int
    ) throws(ExternalAssociatedTripleClassError<Element, String, Bool>) -> Int
}

public struct RealExternalWideAssociatedClassTypedErrorProbe:
    ExternalWideAssociatedClassTypedErrorProbe
{
    public init() {}

    public func load(
        _ code: Int
    ) throws(ExternalAssociatedTripleClassError<Int, String, Bool>) -> Int {
        if code != 0 {
            throw ExternalAssociatedTripleClassError(code, "wide", true)
        }
        return 10
    }
}

public protocol ExternalConstrainedAssociatedClassTypedErrorProbe<Element> {
    associatedtype Element: Hashable

    func load(_ code: Int) throws(ExternalConstrainedAssociatedClassError<Element>) -> Int
}

public struct RealExternalConstrainedAssociatedClassTypedErrorProbe:
    ExternalConstrainedAssociatedClassTypedErrorProbe
{
    public init() {}

    public func load(
        _ code: Int
    ) throws(ExternalConstrainedAssociatedClassError<Int>) -> Int {
        if code != 0 { throw ExternalConstrainedAssociatedClassError(code) }
        return 10
    }
}

public protocol ExternalExplicitAssociatedClassTypedErrorProbe<Element> {
    associatedtype Element

    func load() throws(ExternalAssociatedClassError<Element>) -> Int
}

public struct RealExternalExplicitAssociatedClassTypedErrorProbe:
    ExternalExplicitAssociatedClassTypedErrorProbe
{
    public init() {}

    public func load() throws(ExternalAssociatedClassError<Int>) -> Int { 1 }
}

public enum ExternalAssociatedLeafError: Error {
    case failed
}

public protocol ExternalStringlyAssociatedClassTypedErrorProbe<Failure> {
    associatedtype Failure: Error

    func load() throws(ExternalAssociatedClassError<Failure>) -> Int
}

public struct RealExternalStringlyAssociatedClassTypedErrorProbe:
    ExternalStringlyAssociatedClassTypedErrorProbe
{
    public init() {}

    public func load() throws(ExternalAssociatedClassError<ExternalAssociatedLeafError>) -> Int { 1 }
}

public struct ExternalAssociatedErrorValue<Value> {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public struct ExternalAssociatedGenericStructError<Value>:
    Error, @unchecked Sendable
{
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

public enum ExternalAssociatedGenericEnumError<Value>:
    Error, @unchecked Sendable
{
    case value(Value)
}

public protocol ExternalOptionalAssociatedClassErrorProbe<Element> {
    associatedtype Element

    func load() throws(ExternalAssociatedClassError<Element?>) -> Int
}

public struct RealExternalOptionalAssociatedClassErrorProbe:
    ExternalOptionalAssociatedClassErrorProbe
{
    public init() {}

    public func load() throws(ExternalAssociatedClassError<Int?>) -> Int { 1 }
}

public protocol ExternalValueWrappedAssociatedClassErrorProbe<Element> {
    associatedtype Element

    func load() throws(ExternalAssociatedClassError<ExternalAssociatedErrorValue<Element>>) -> Int
}

public struct RealExternalValueWrappedAssociatedClassErrorProbe:
    ExternalValueWrappedAssociatedClassErrorProbe
{
    public init() {}

    public func load() throws(ExternalAssociatedClassError<ExternalAssociatedErrorValue<Int>>) -> Int { 1 }
}

public protocol ExternalGenericStructAssociatedErrorProbe<Element> {
    associatedtype Element

    func load() throws(ExternalAssociatedGenericStructError<Element>) -> Int
    func asynchronouslyLoad(
        _ code: Int
    ) async throws(ExternalAssociatedGenericStructError<Element>) -> Int
}

public struct RealExternalGenericStructAssociatedErrorProbe:
    ExternalGenericStructAssociatedErrorProbe
{
    public init() {}

    public func load() throws(ExternalAssociatedGenericStructError<Int>) -> Int { 1 }

    public func asynchronouslyLoad(
        _ code: Int
    ) async throws(ExternalAssociatedGenericStructError<Int>) -> Int {
        if code != 0 { throw ExternalAssociatedGenericStructError(code) }
        return 10
    }
}

public protocol ExternalGenericEnumAssociatedErrorProbe<Element> {
    associatedtype Element

    func load() throws(ExternalAssociatedGenericEnumError<Element>) -> Int
    func asynchronouslyLoad(
        _ code: Int
    ) async throws(ExternalAssociatedGenericEnumError<Element>) -> Int
}

public struct RealExternalGenericEnumAssociatedErrorProbe:
    ExternalGenericEnumAssociatedErrorProbe
{
    public init() {}

    public func load() throws(ExternalAssociatedGenericEnumError<Int>) -> Int { 1 }

    public func asynchronouslyLoad(
        _ code: Int
    ) async throws(ExternalAssociatedGenericEnumError<Int>) -> Int {
        if code != 0 { throw .value(code) }
        return 20
    }
}
