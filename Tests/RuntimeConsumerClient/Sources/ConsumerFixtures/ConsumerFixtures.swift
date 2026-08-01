/// A value whose client ABI is resilient to this module's future evolution.
public struct ExternalReservation: Comparable, Equatable, Sendable {
    public let start: UInt64
    public let end: UInt64

    public init(start: UInt64, end: UInt64) {
        self.start = start
        self.end = end
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }
}

/// A same-sized direct-passing control.
@frozen public struct FrozenExternalPoint: Equatable, Sendable {
    public let x: UInt64
    public let y: UInt64

    public init(x: UInt64, y: UInt64) {
        self.x = x
        self.y = y
    }
}
