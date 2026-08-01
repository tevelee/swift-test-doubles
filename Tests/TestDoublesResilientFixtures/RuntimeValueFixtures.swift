/// A public value whose layout is resilient to clients of this module.
///
/// Although its current layout is two machine words, clients must pass it by
/// address because this module is built with library evolution enabled and the
/// declaration is not frozen.
public struct ResilientValueArgument: Equatable, Sendable {
    public let first: UInt64
    public let second: UInt64

    public init(first: UInt64, second: UInt64) {
        self.first = first
        self.second = second
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
