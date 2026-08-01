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

/// A non-frozen nominal shell around a tuple whose first member is itself
/// resilient to this module's future evolution.
public struct ReservationEnvelope: Sendable {
    public let payload: (ExternalReservation, UInt64)

    public init(reservation: ExternalReservation, identifier: UInt64) {
        payload = (reservation, identifier)
    }
}

/// A generic shell representative of a model type owned by a third-party
/// library-evolution module.
public struct ReservationBox<Value: Sendable>: Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

/// A recursive generic model such as a delivery itinerary or document tree.
public indirect enum ReservationTree<Value: Sendable>: Sendable {
    case value(Value)
    case child(ReservationTree)
}

/// A non-frozen error emitted by the same external module as the payload.
public enum ReservationFailure: Error, Sendable {
    case unavailable(code: UInt64)
}

/// A production-style dependency surface exposed to an external test client.
public protocol DeliveryGateway: Sendable {
    func schedule(
        destination: URL,
        window: ClosedRange<ExternalReservation>,
        notes: URL??
    ) -> Int

    func day(_ window: ClosedRange<Date>) -> Int

    func classify(
        after: PartialRangeFrom<ExternalReservation>,
        through: PartialRangeThrough<ExternalReservation>,
        before: PartialRangeUpTo<ExternalReservation>
    ) -> UInt64

    func importBatch(
        urls: [URL],
        reservations: [String: ExternalReservation]
    ) -> Int

    static func tier(_ reservation: ExternalReservation) -> UInt64

    func map(_ point: FrozenExternalPoint) -> UInt64

    func settle(_ value: (ExternalReservation, UInt64)?) -> Int

    func review(_ reservation: ExternalReservation?) -> UInt64

    func deliver(_ value: ReservationEnvelope) -> Int

    func package(_ value: ReservationBox<(ExternalReservation, UInt64)>) -> Int

    func resolve(_ value: Result<(ExternalReservation, UInt64), Never>) -> Int

    func resolveOutcome(
        _ value: Result<(ExternalReservation, UInt64), ReservationFailure>
    ) -> String

    func inspect(_ value: ReservationTree<ExternalReservation>) -> Int

    func reserve(
        _ value: ReservationBox<(ExternalReservation, UInt64)>,
        marker: UInt64
    ) async -> Int

    func confirm(_ reservation: ExternalReservation) async throws -> UInt64

    func tally(_ reservations: ExternalReservation...) -> UInt64
}

public protocol ReservationSource {
    func currentReservation() -> ExternalReservation
}

/// A typical application boundary that combines several Foundation values
/// originating in distinct library-evolution modules.
public protocol FoundationArchiveGateway {
    func archive(
        source: URL,
        bytes: Data,
        interval: DateInterval,
        locale: Locale,
        timeZone: TimeZone,
        amount: Decimal
    ) -> Int
}

/// An API that receives optional values after Swift implicitly promotes a
/// generic matcher result through one or more optional layers.
public protocol OptionalDestinationGateway {
    func deliver(_ destination: URL??) -> Int
    func cascade(_ destination: URL???) -> Int
}

/// A reporting boundary that erases the application's concrete error type.
public protocol FailureReporter {
    func report(_ error: any Error) -> String
}

/// A payload protocol that represents an opaque domain-model argument.
public protocol ReportPayload {
    var summary: String { get }
}

public struct ExternalReportPayload: ReportPayload, Sendable {
    public let summary: String

    public init(summary: String) {
        self.summary = summary
    }
}

public protocol PayloadReporter {
    func report(_ payload: any ReportPayload) -> String
}

public protocol SendablePayloadReporter {
    func report(_ payload: any ReportPayload & Sendable) -> String
}

public final class ExternalReferenceReportPayload: ReportPayload {
    public let summary: String

    public init(summary: String) {
        self.summary = summary
    }
}

public protocol ClassConstrainedPayloadReporter {
    func report(_ payload: any ReportPayload & AnyObject) -> String
}

/// A deliberately unsupported mixed tuple transport. The first member is
/// resilient to this module while the second is a direct scalar.
public protocol MixedTupleGateway {
    func submit(_ payload: (ExternalReservation, UInt64)) -> Int
}

/// A logging dependency that uses call-site expression syntax.
public protocol AutoclosureDeliveryLog {
    func record(_ message: @autoclosure @escaping () -> String)
}

/// Verifies that raw-mangling convention detection does not confuse an
/// identifier's spelling with an autoclosure type operator.
public protocol XKFAutoclosureDeliveryLog {
    func record(_ message: @autoclosure @escaping () -> String)
}

/// A logging dependency that evaluates its call-site expression immediately.
public protocol EagerAutoclosureDeliveryLog {
    func record(_ message: @autoclosure () -> String)
}

/// An eager metric dependency whose autoclosure returns a scalar instead of a
/// standard-library value with a specialized mangling.
public protocol EagerIntegerAutoclosureDeliveryLog {
    func record(_ value: @autoclosure () -> Int)
}

/// A UI-facing dependency whose requirements are isolated to the main actor.
@MainActor
public protocol MainActorReservationGateway {
    func review(_ reservation: ExternalReservation) -> UInt64
}

/// A property-backed store such as an injected preference or configuration
/// boundary. Swift requires every settable protocol property to be gettable.
public protocol ReservationStore {
    var reservation: ExternalReservation { get set }
}

/// A configured session created by a protocol initializer.
public protocol ReservationSession {
    init(seed: ExternalReservation)
    func identifier() -> UInt64
}

/// An asynchronously configured session such as one that performs setup I/O.
public protocol AsyncReservationSession {
    init(seed: ExternalReservation) async throws
    func identifier() -> UInt64
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

    public func classify(
        after: PartialRangeFrom<ExternalReservation>,
        through: PartialRangeThrough<ExternalReservation>,
        before: PartialRangeUpTo<ExternalReservation>
    ) -> UInt64 {
        after.lowerBound.start ^ through.upperBound.end ^ before.upperBound.start
    }

    public func importBatch(
        urls: [URL],
        reservations: [String: ExternalReservation]
    ) -> Int {
        urls.count
            + reservations.values.reduce(0) { partial, reservation in
                partial + Int(reservation.start ^ reservation.end)
            }
    }

    public func map(_ point: FrozenExternalPoint) -> UInt64 {
        point.x ^ point.y
    }

    public func settle(_ value: (ExternalReservation, UInt64)?) -> Int {
        guard let value else { return 0 }
        return Int(value.0.start ^ value.0.end ^ value.1)
    }

    public func review(_ reservation: ExternalReservation?) -> UInt64 {
        guard let reservation else { return 0 }
        return reservation.start ^ reservation.end
    }

    public func deliver(_ value: ReservationEnvelope) -> Int {
        Int(value.payload.0.start ^ value.payload.0.end ^ value.payload.1)
    }

    public func package(
        _ value: ReservationBox<(ExternalReservation, UInt64)>
    ) -> Int {
        Int(value.value.0.start ^ value.value.0.end ^ value.value.1)
    }

    public func resolve(
        _ value: Result<(ExternalReservation, UInt64), Never>
    ) -> Int {
        switch value {
            case .success(let value):
                return Int(value.0.start ^ value.0.end ^ value.1)
            case .failure(let impossible):
                switch impossible {}
        }
    }

    public static func tier(_ reservation: ExternalReservation) -> UInt64 {
        reservation.start ^ reservation.end
    }

    public func resolveOutcome(
        _ value: Result<(ExternalReservation, UInt64), ReservationFailure>
    ) -> String {
        switch value {
            case .success(let value):
                return "reservation:\(value.0.start ^ value.0.end ^ value.1)"
            case .failure(.unavailable(let code)):
                return "failure:\(code)"
        }
    }

    public func inspect(_ value: ReservationTree<ExternalReservation>) -> Int {
        switch value {
            case .value(let reservation):
                return Int(reservation.start ^ reservation.end)
            case .child(let value):
                return inspect(value)
        }
    }

    public func reserve(
        _ value: ReservationBox<(ExternalReservation, UInt64)>,
        marker: UInt64
    ) async -> Int {
        Int(value.value.0.start ^ value.value.0.end ^ value.value.1 ^ marker)
    }

    public func confirm(_ reservation: ExternalReservation) async throws -> UInt64 {
        reservation.start ^ reservation.end
    }

    public func tally(_ reservations: ExternalReservation...) -> UInt64 {
        reservations.reduce(0) { $0 ^ $1.start ^ $1.end }
    }
}

public struct LiveReservationSource: ReservationSource {
    public init() {}

    public func currentReservation() -> ExternalReservation {
        ExternalReservation(start: 1, end: 2)
    }
}

public struct LiveFoundationArchiveGateway: FoundationArchiveGateway {
    public init() {}

    public func archive(
        source: URL,
        bytes: Data,
        interval: DateInterval,
        locale: Locale,
        timeZone: TimeZone,
        amount: Decimal
    ) -> Int {
        archiveScore(
            source: source,
            bytes: bytes,
            interval: interval,
            locale: locale,
            timeZone: timeZone,
            amount: amount
        )
    }
}

public struct LiveAutoclosureDeliveryLog: AutoclosureDeliveryLog {
    public init() {}

    public func record(_ message: @autoclosure @escaping () -> String) {
        _ = message()
    }
}

public struct LiveXKFAutoclosureDeliveryLog: XKFAutoclosureDeliveryLog {
    public init() {}

    public func record(_ message: @autoclosure @escaping () -> String) {
        _ = message()
    }
}

public struct LiveEagerAutoclosureDeliveryLog: EagerAutoclosureDeliveryLog {
    public init() {}

    public func record(_ message: @autoclosure () -> String) {
        _ = message()
    }
}

public struct LiveEagerIntegerAutoclosureDeliveryLog:
    EagerIntegerAutoclosureDeliveryLog
{
    public init() {}

    public func record(_ value: @autoclosure () -> Int) {
        _ = value()
    }
}

private func archiveScore(
    source: URL,
    bytes: Data,
    interval: DateInterval,
    locale: Locale,
    timeZone: TimeZone,
    amount: Decimal
) -> Int {
    source.absoluteString.count
        + bytes.count
        + Int(interval.duration)
        + locale.identifier.count
        + timeZone.secondsFromGMT()
        + NSDecimalNumber(decimal: amount).intValue
}

public struct LiveReservationStore: ReservationStore {
    public var reservation: ExternalReservation

    public init(reservation: ExternalReservation) {
        self.reservation = reservation
    }
}

@MainActor
public struct LiveMainActorReservationGateway: MainActorReservationGateway {
    public init() {}

    public func review(_ reservation: ExternalReservation) -> UInt64 {
        reservation.start ^ reservation.end
    }
}

public struct LiveReservationSession: ReservationSession {
    public let seed: ExternalReservation

    public init(seed: ExternalReservation) {
        self.seed = seed
    }

    public func identifier() -> UInt64 {
        seed.start ^ seed.end
    }
}

public struct LiveAsyncReservationSession: AsyncReservationSession {
    public let seed: ExternalReservation

    public init(seed: ExternalReservation) async throws {
        self.seed = seed
    }

    public func identifier() -> UInt64 {
        seed.start ^ seed.end
    }
}
