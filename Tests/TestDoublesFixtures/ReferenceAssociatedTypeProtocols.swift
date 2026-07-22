public final class ExternalReferenceAssociatedBox: @unchecked Sendable {
    public let id: Int

    public init(id: Int) {
        self.id = id
    }
}

public struct ExternalReferenceFixedFailure: Error, Equatable, Sendable {
    public let code: Int

    public init(code: Int) {
        self.code = code
    }
}

public final class ExternalReferenceAssociatedFailure:
    Error, @unchecked Sendable
{
    public let code: Int

    public init(code: Int) {
        self.code = code
    }
}

public final class ExternalAlternateReferenceAssociatedFailure:
    Error, @unchecked Sendable
{
    public let code: Int

    public init(code: Int) {
        self.code = code
    }
}

public protocol ExternalReferenceAssociatedProbe<Element> {
    associatedtype Element: AnyObject

    func accept(_ value: Element)
    func transform(_ value: borrowing Element) -> Element
    func consume(_ value: consuming Element)
    func optional(_ value: Element?) -> Element?
    func asynchronous(_ value: Element) async -> Element
    func consumeAsynchronously(_ value: consuming Element) async
    func throwing(
        _ value: Element
    ) throws(ExternalReferenceFixedFailure) -> Element
    func throwingAsynchronously(
        _ value: Element?
    ) async throws(ExternalReferenceFixedFailure) -> Element?
}

public struct RealExternalReferenceAssociatedProbe:
    ExternalReferenceAssociatedProbe
{
    public init() {}

    public func accept(_ value: ExternalReferenceAssociatedBox) {}

    public func transform(
        _ value: borrowing ExternalReferenceAssociatedBox
    ) -> ExternalReferenceAssociatedBox {
        copy value
    }

    public func consume(_ value: consuming ExternalReferenceAssociatedBox) {}

    public func optional(
        _ value: ExternalReferenceAssociatedBox?
    ) -> ExternalReferenceAssociatedBox? {
        value
    }

    public func asynchronous(
        _ value: ExternalReferenceAssociatedBox
    ) async -> ExternalReferenceAssociatedBox {
        value
    }

    public func consumeAsynchronously(
        _ value: consuming ExternalReferenceAssociatedBox
    ) async {}

    public func throwing(
        _ value: ExternalReferenceAssociatedBox
    ) throws(ExternalReferenceFixedFailure) -> ExternalReferenceAssociatedBox {
        value
    }

    public func throwingAsynchronously(
        _ value: ExternalReferenceAssociatedBox?
    ) async throws(ExternalReferenceFixedFailure) -> ExternalReferenceAssociatedBox? {
        value
    }
}

public protocol ExternalReferenceAssociatedFailureProbe<Failure> {
    associatedtype Failure: Error & AnyObject

    func load(_ shouldFail: Bool) throws(Failure) -> Int
    func loadAsynchronously(_ shouldFail: Bool) async throws(Failure) -> Int
}

public struct RealExternalReferenceAssociatedFailureProbe:
    ExternalReferenceAssociatedFailureProbe
{
    public init() {}

    public func load(
        _ shouldFail: Bool
    ) throws(ExternalReferenceAssociatedFailure) -> Int {
        if shouldFail {
            throw ExternalReferenceAssociatedFailure(code: 41)
        }
        return 40
    }

    public func loadAsynchronously(
        _ shouldFail: Bool
    ) async throws(ExternalReferenceAssociatedFailure) -> Int {
        if shouldFail {
            throw ExternalReferenceAssociatedFailure(code: 43)
        }
        return 42
    }
}

public protocol ExternalExplicitReferenceAssociatedProbe<Element> {
    associatedtype Element: AnyObject

    func transform(_ value: Element) -> Element
    func optional(_ value: Element?) -> Element?
    func consume(_ value: consuming Element)
    func asynchronous(_ value: Element) async -> Element
}

public protocol ExternalExplicitReferenceAssociatedFailureProbe<Failure> {
    associatedtype Failure: Error & AnyObject

    func load() throws(Failure) -> Int
}

public protocol ExternalReferenceAssociatedIdentityProbe<Element> {
    associatedtype Element: AnyObject

    func transform(_ value: Element) -> Element
}

public struct RealExternalReferenceAssociatedIdentityProbe:
    ExternalReferenceAssociatedIdentityProbe
{
    public init() {}

    public func transform(
        _ value: ExternalReferenceAssociatedBox
    ) -> ExternalReferenceAssociatedBox {
        value
    }
}

public protocol ExternalReferenceAssociatedMarker: AnyObject {}

extension ExternalReferenceAssociatedBox: ExternalReferenceAssociatedMarker {}

public protocol ExternalUnsupportedReferenceArrayProbe<Element> {
    associatedtype Element: AnyObject

    func load() -> [Element]
}

public struct RealExternalUnsupportedReferenceArrayProbe:
    ExternalUnsupportedReferenceArrayProbe
{
    public init() {}

    public func load() -> [ExternalReferenceAssociatedBox] { [] }
}

public protocol ExternalUnsupportedNestedOptionalReferenceProbe<Element> {
    associatedtype Element: AnyObject

    func load() -> Element??
}

public struct RealExternalUnsupportedNestedOptionalReferenceProbe:
    ExternalUnsupportedNestedOptionalReferenceProbe
{
    public init() {}

    public func load() -> ExternalReferenceAssociatedBox?? { nil }
}
