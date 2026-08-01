import Foundation

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

/// A production-style dependency surface exposed to an external test client.
public protocol DeliveryGateway: Sendable {
    func schedule(
        destination: URL,
        window: ClosedRange<ExternalReservation>,
        notes: URL??
    ) -> Int

    func day(_ window: ClosedRange<Date>) -> Int

    func map(_ point: FrozenExternalPoint) -> UInt64
}

public protocol ReservationSource {
    func currentReservation() -> ExternalReservation
}

public struct LiveDeliveryGateway: DeliveryGateway, Sendable {
    public init() {}

    public func schedule(
        destination: URL,
        window: ClosedRange<ExternalReservation>,
        notes: URL??
    ) -> Int {
        destination.absoluteString.count
            + Int(window.lowerBound.start)
            + (notes == nil ? 0 : 1)
    }

    public func day(_ window: ClosedRange<Date>) -> Int {
        Int(window.lowerBound.timeIntervalSinceReferenceDate)
    }

    public func map(_ point: FrozenExternalPoint) -> UInt64 {
        point.x ^ point.y
    }
}

public struct LiveReservationSource: ReservationSource {
    public init() {}

    public func currentReservation() -> ExternalReservation {
        ExternalReservation(start: 1, end: 2)
    }
}
