/// A public value whose layout is resilient to clients of this module.
///
/// Although its current layout is two machine words, clients must pass it by
/// address because this module is built with library evolution enabled and the
/// declaration is not frozen.
public struct ResilientValueArgument: Comparable, Sendable {
    public let first: UInt64
    public let second: UInt64

    public init(first: UInt64, second: UInt64) {
        self.first = first
        self.second = second
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.first, lhs.second) < (rhs.first, rhs.second)
    }
}

/// A direct-passing control with the same stored layout as
/// ``ResilientValueArgument``.
@frozen public struct FrozenValueArgument: Equatable, Sendable {
    public let first: UInt64
    public let second: UInt64

    public init(first: UInt64, second: UInt64) {
        self.first = first
        self.second = second
    }
}

/// A direct-passing floating-point aggregate used to prove that stale vector
/// registers cannot be mistaken for a resilient indirect argument.
@frozen public struct FrozenFloatingValueArgument: Equatable, Sendable {
    public let first: Double
    public let second: Double

    public init(first: Double, second: Double) {
        self.first = first
        self.second = second
    }
}

/// A non-frozen enum is likewise resilient to clients of this module, even
/// though each current case has a compact tag-only representation.
public enum ResilientEnumArgument: Sendable {
    case pending
    case confirmed
}

/// A non-frozen typed error whose transport is resilient to clients of this
/// module.
public struct ResilientTypedError: Error, Equatable, Sendable {
    public let code: Int

    public init(code: Int) {
        self.code = code
    }
}

/// A frozen control for typed-error transport tests.
@frozen public struct TypedThrowsPayloadError: Error, Equatable, Sendable {
    public let code: Int
    public let sequence: Int

    public init(code: Int, sequence: Int) {
        self.code = code
        self.sequence = sequence
    }
}

/// Result shapes used to assert the runtime's fail-closed handling of values
/// whose public ABI cannot reveal frozen-ness to a client.
public protocol ResilientValueResultABIProbe {
    func makeValue() -> ResilientValueArgument
}

/// A frozen control for ``ResilientValueResultABIProbe``.
public protocol FrozenValueResultABIProbe {
    func makeValue() -> FrozenValueArgument
}
