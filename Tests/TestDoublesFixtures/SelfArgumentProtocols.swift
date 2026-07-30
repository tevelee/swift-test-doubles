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

public protocol ExternalSelfSubscriptArgumentProbe {
    subscript(_ value: Self) -> Int { get set }
    subscript(optional value: Self?) -> Int { get set }
}

public struct RealExternalSelfSubscriptArgumentProbe:
    ExternalSelfSubscriptArgumentProbe
{
    public init() {}

    public subscript(
        _ value: RealExternalSelfSubscriptArgumentProbe
    ) -> Int {
        get { 0 }
        set {}
    }

    public subscript(
        optional value: RealExternalSelfSubscriptArgumentProbe?
    ) -> Int {
        get { 0 }
        set {}
    }
}

public protocol ExternalClassSelfSubscriptArgumentProbe: AnyObject {
    subscript(_ value: Self) -> Int { get set }
    subscript(optional value: Self?) -> Int { get set }
}

public final class RealExternalClassSelfSubscriptArgumentProbe:
    ExternalClassSelfSubscriptArgumentProbe
{
    public init() {}

    public subscript(
        _ value: RealExternalClassSelfSubscriptArgumentProbe
    ) -> Int {
        get { 0 }
        set {}
    }

    public subscript(
        optional value: RealExternalClassSelfSubscriptArgumentProbe?
    ) -> Int {
        get { 0 }
        set {}
    }
}

public protocol ExternalThrowingSelfSubscriptArgumentProbe {
    subscript(_ value: Self) -> Int { get throws }
    subscript(optional value: Self?) -> Int { get throws }
    subscript(typed value: Self) -> Int {
        get throws(ExternalThrowingSelfArgumentError)
    }
}

public struct RealExternalThrowingSelfSubscriptArgumentProbe:
    ExternalThrowingSelfSubscriptArgumentProbe
{
    public init() {}

    public subscript(
        _ value: RealExternalThrowingSelfSubscriptArgumentProbe
    ) -> Int {
        get throws { 0 }
    }

    public subscript(
        optional value: RealExternalThrowingSelfSubscriptArgumentProbe?
    ) -> Int {
        get throws { 0 }
    }

    public subscript(
        typed value: RealExternalThrowingSelfSubscriptArgumentProbe
    ) -> Int {
        get throws(ExternalThrowingSelfArgumentError) { 0 }
    }
}

public protocol ExternalStaticSelfSubscriptArgumentProbe {
    static subscript(_ value: Self) -> Int { get set }
    static subscript(optional value: Self?) -> Int { get set }
}

public struct RealExternalStaticSelfSubscriptArgumentProbe:
    ExternalStaticSelfSubscriptArgumentProbe
{
    public init() {}

    public static subscript(
        _ value: RealExternalStaticSelfSubscriptArgumentProbe
    ) -> Int {
        get { 0 }
        set {}
    }

    public static subscript(
        optional value: RealExternalStaticSelfSubscriptArgumentProbe?
    ) -> Int {
        get { 0 }
        set {}
    }
}

public enum ExternalStaticSelfArgumentError: Error, Equatable {
    case rejected
}

public protocol ExternalStaticSelfArgumentProbe {
    static func accept(_ value: Self)
    static func acceptOptional(_ value: Self?)
    static func reject(_ value: Self) throws
    static func rejectTyped(
        _ value: Self
    ) throws(ExternalStaticSelfArgumentError)
}

public struct RealExternalStaticSelfArgumentProbe:
    ExternalStaticSelfArgumentProbe
{
    public init() {}

    public static func accept(
        _ value: RealExternalStaticSelfArgumentProbe
    ) {}

    public static func acceptOptional(
        _ value: RealExternalStaticSelfArgumentProbe?
    ) {}

    public static func reject(
        _ value: RealExternalStaticSelfArgumentProbe
    ) throws {}

    public static func rejectTyped(
        _ value: RealExternalStaticSelfArgumentProbe
    ) throws(ExternalStaticSelfArgumentError) {}
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

public enum ExternalThrowingSelfArgumentError: Error, Equatable {
    case rejected
}

public protocol ExternalThrowingSelfArgumentProbe {
    func accept(_ value: Self) throws
    func borrow(_ value: borrowing Self) throws
    func consume(_ value: consuming Self) throws
    func acceptOptional(_ value: Self?) throws
    func consumeOptional(_ value: consuming Self?) throws
    func acceptTyped(
        _ value: Self
    ) throws(ExternalThrowingSelfArgumentError)
    func consumeTyped(
        _ value: consuming Self
    ) throws(ExternalThrowingSelfArgumentError)
    func acceptOptionalTyped(
        _ value: Self?
    ) throws(ExternalThrowingSelfArgumentError)
    func consumeOptionalTyped(
        _ value: consuming Self?
    ) throws(ExternalThrowingSelfArgumentError)
}

public struct RealExternalThrowingSelfArgumentProbe:
    ExternalThrowingSelfArgumentProbe
{
    public init() {}

    public func accept(_ value: Self) throws {}

    public func borrow(_ value: borrowing Self) throws {}

    public func consume(_ value: consuming Self) throws {}

    public func acceptOptional(_ value: Self?) throws {}

    public func consumeOptional(_ value: consuming Self?) throws {}

    public func acceptTyped(
        _ value: Self
    ) throws(ExternalThrowingSelfArgumentError) {}

    public func consumeTyped(
        _ value: consuming Self
    ) throws(ExternalThrowingSelfArgumentError) {}

    public func acceptOptionalTyped(
        _ value: Self?
    ) throws(ExternalThrowingSelfArgumentError) {}

    public func consumeOptionalTyped(
        _ value: consuming Self?
    ) throws(ExternalThrowingSelfArgumentError) {}
}

public protocol ExternalThrowingClassSelfArgumentProbe: AnyObject {
    func consume(_ value: consuming Self) throws
}

public final class RealExternalThrowingClassSelfArgumentProbe:
    ExternalThrowingClassSelfArgumentProbe
{
    public init() {}

    public func consume(
        _ value: consuming RealExternalThrowingClassSelfArgumentProbe
    ) throws {}
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
