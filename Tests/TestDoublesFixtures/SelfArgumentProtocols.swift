public protocol ExternalSelfArgumentProbe {
    func accept(_ value: Self)
    func borrow(_ value: borrowing Self)
    func consume(_ value: consuming Self)
    func acceptOptional(_ value: Self?)
    func consumeOptional(_ value: consuming Self?)
    func acceptAsynchronously(_ value: Self) async
    func consumeAsynchronously(_ value: consuming Self) async
    func roundTrip(_ value: Self) -> Self
    func optionalRoundTrip(_ value: Self?) -> Self?
    func marker() -> Int
}

public struct RealExternalSelfArgumentProbe: ExternalSelfArgumentProbe {
    public init() {}

    public func accept(_ value: Self) {}

    public func borrow(_ value: borrowing Self) {}

    public func consume(_ value: consuming Self) {}

    public func acceptOptional(_ value: Self?) {}

    public func consumeOptional(_ value: consuming Self?) {}

    public func acceptAsynchronously(_ value: Self) async {}

    public func consumeAsynchronously(_ value: consuming Self) async {}

    public func roundTrip(_ value: Self) -> Self { value }

    public func optionalRoundTrip(_ value: Self?) -> Self? { value }

    public func marker() -> Int { 0 }
}

public protocol ExternalClassSelfArgumentProbe: AnyObject {
    func accept(_ value: Self)
    func borrow(_ value: borrowing Self)
    func consume(_ value: consuming Self)
    func acceptOptional(_ value: Self?)
    func consumeOptional(_ value: consuming Self?)
    func acceptAsynchronously(_ value: Self) async
    func consumeAsynchronously(_ value: consuming Self) async
    func roundTrip(_ value: Self) -> Self
    func optionalRoundTrip(_ value: Self?) -> Self?
    func marker() -> Int
}

public final class RealExternalClassSelfArgumentProbe:
    ExternalClassSelfArgumentProbe
{
    public init() {}

    public func accept(_ value: RealExternalClassSelfArgumentProbe) {}

    public func borrow(
        _ value: borrowing RealExternalClassSelfArgumentProbe
    ) {}

    public func consume(
        _ value: consuming RealExternalClassSelfArgumentProbe
    ) {}

    public func acceptOptional(
        _ value: RealExternalClassSelfArgumentProbe?
    ) {}

    public func consumeOptional(
        _ value: consuming RealExternalClassSelfArgumentProbe?
    ) {}

    public func acceptAsynchronously(
        _ value: RealExternalClassSelfArgumentProbe
    ) async {}

    public func consumeAsynchronously(
        _ value: consuming RealExternalClassSelfArgumentProbe
    ) async {}

    public func roundTrip(
        _ value: RealExternalClassSelfArgumentProbe
    ) -> Self {
        self
    }

    public func optionalRoundTrip(
        _ value: RealExternalClassSelfArgumentProbe?
    ) -> Self? {
        value == nil ? nil : self
    }

    public func marker() -> Int { 0 }
}

public protocol ExternalInheritedClassSelfArgumentProbe:
    ExternalSelfArgumentProbe, AnyObject
{}

public final class RealExternalInheritedClassSelfArgumentProbe:
    ExternalInheritedClassSelfArgumentProbe
{
    public init() {}

    public func accept(
        _ value: RealExternalInheritedClassSelfArgumentProbe
    ) {}

    public func borrow(
        _ value: borrowing RealExternalInheritedClassSelfArgumentProbe
    ) {}

    public func consume(
        _ value: consuming RealExternalInheritedClassSelfArgumentProbe
    ) {}

    public func acceptOptional(
        _ value: RealExternalInheritedClassSelfArgumentProbe?
    ) {}

    public func consumeOptional(
        _ value: consuming RealExternalInheritedClassSelfArgumentProbe?
    ) {}

    public func acceptAsynchronously(
        _ value: RealExternalInheritedClassSelfArgumentProbe
    ) async {}

    public func consumeAsynchronously(
        _ value: consuming RealExternalInheritedClassSelfArgumentProbe
    ) async {}

    public func roundTrip(
        _ value: RealExternalInheritedClassSelfArgumentProbe
    ) -> Self {
        self
    }

    public func optionalRoundTrip(
        _ value: RealExternalInheritedClassSelfArgumentProbe?
    ) -> Self? {
        value == nil ? nil : self
    }

    public func marker() -> Int { 0 }
}

public protocol ExternalInoutSelfArgumentProbe {
    func update(_ value: inout Self)
}

public struct RealExternalInoutSelfArgumentProbe:
    ExternalInoutSelfArgumentProbe
{
    public init() {}

    public func update(_ value: inout Self) {}
}

public protocol ExternalNestedOptionalSelfArgumentProbe {
    func accept(_ value: Self??)
}

public struct RealExternalNestedOptionalSelfArgumentProbe:
    ExternalNestedOptionalSelfArgumentProbe
{
    public init() {}

    public func accept(_ value: Self??) {}
}

public protocol ExternalArraySelfArgumentProbe {
    func accept(_ value: [Self])
}

public struct RealExternalArraySelfArgumentProbe:
    ExternalArraySelfArgumentProbe
{
    public init() {}

    public func accept(_ value: [Self]) {}
}

public enum ExternalThrowingSelfArgumentError: Error {
    case rejected
}

public protocol ExternalThrowingSelfArgumentProbe {
    func accept(_ value: Self) throws
}

public struct RealExternalThrowingSelfArgumentProbe:
    ExternalThrowingSelfArgumentProbe
{
    public init() {}

    public func accept(_ value: Self) throws {}
}

public protocol ExternalArgumentOnlySelfProbe {
    func accept(_ value: Self)
    func acceptOptional(_ value: Self?)
    func marker() -> Int
}

public struct RealExternalArgumentOnlySelfProbe:
    ExternalArgumentOnlySelfProbe
{
    public init() {}

    public func accept(_ value: Self) {}

    public func acceptOptional(_ value: Self?) {}

    public func marker() -> Int { 0 }
}
