import Foundation
#if canImport(FoundationNetworking) && !os(Android)
    import FoundationNetworking
#endif

/// A deliberately simple imported protocol used to smoke-test ordinary
/// out-of-package consumers independently of resilient ABI stress fixtures.
public protocol RuntimeConsumerSmokeService: Sendable {
    func value(for identifier: Int) -> Int
}

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

    func sum(_ values: ArraySlice<Int>) -> Int

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

public protocol ImportedDataSource: Sendable {
    func loadData() async throws -> Data
}

public protocol ImportedPathDataSource: Sendable {
    func read(path: String) throws -> Data
}

public protocol ImportedDataSubscriptSource: Sendable {
    subscript(path: String) -> Data { get }
}

#if compiler(>=6.4)
    public protocol ForwardingFoundationResultSource: Sendable {
        func data(for identifier: Int) -> Data
        func identifier(for value: Int) -> UUID
    }

    public struct LiveForwardingFoundationResultSource:
        ForwardingFoundationResultSource
    {
        public init() {}

        public func data(for identifier: Int) -> Data {
            Data([UInt8(identifier)])
        }

        public func identifier(for value: Int) -> UUID {
            UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, UInt8(value)
                )
            )
        }
    }
#endif

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol CommonFoundationResultSource: Sendable {
    var currentURL: URL { get }
    func data() -> Data
    func date() throws -> Date
    func identifier() async -> UUID
    func interval() async throws -> DateInterval
    func calendar() async throws -> Calendar
    func locale() -> Locale
    func timeZone() throws -> TimeZone
    func indexPath() async -> IndexPath
    func indexSet() async throws -> IndexSet
    func characterSet() -> CharacterSet
    func decimal() throws -> Decimal
    func notificationName() async -> Notification.Name
    func notification() async throws -> Notification
    func attributedString() -> AttributedString
    func personNameComponents() async throws -> PersonNameComponents
    #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
        func request() async throws -> URLRequest
    #endif
}

public protocol ParameterizedFoundationResultSource: Sendable {
    func identifier(for value: Int, namespace: String) async -> UUID
}

public typealias ThrowingDataLoader = @Sendable (String) throws -> Data

public protocol FoundationClosureArgumentSource: Sendable {
    func byteCount(
        using loader: @escaping ThrowingDataLoader,
        path: String
    ) throws -> Int
}

public protocol FoundationClosureResultSource: Sendable {
    func loader() -> ThrowingDataLoader
}

public protocol UncertainFoundationClosureParameterSource: Sendable {
    func evaluate(_ transform: @escaping @Sendable (Data) -> Int) -> Int
}

public typealias ReservationLoader = @Sendable (String) -> ExternalReservation

public protocol UncertainCustomClosureResultSource: Sendable {
    func loader() -> ReservationLoader
}

#if compiler(>=6.4)
    public typealias AsyncIdentifierLoader = @Sendable (Int) async -> UUID

    public protocol AsyncFoundationClosureResultSource: Sendable {
        func loader() -> AsyncIdentifierLoader
    }
#endif

public protocol EventStreamSource: Sendable {
    func integers() -> AsyncStream<Int>
    func labels() -> AsyncThrowingStream<String, any Error>
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

public protocol DetailedReportPayload {
    var detail: String { get }
}

public struct ExternalReportPayload: ReportPayload, DetailedReportPayload, Sendable {
    public let summary: String
    public let detail: String

    public init(summary: String, detail: String = "") {
        self.summary = summary
        self.detail = detail
    }
}

public protocol PayloadReporter {
    func report(_ payload: any ReportPayload) -> String
}

public protocol SendablePayloadReporter {
    func report(_ payload: any ReportPayload & Sendable) -> String
}

public protocol DetailedPayloadReporter {
    func report(_ payload: any ReportPayload & DetailedReportPayload) -> String
}

public protocol PayloadMetatypeReporter {
    func report(_ type: any ReportPayload.Type) -> String
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

public enum NestedPayloadNamespace {
    public protocol Payload {
        var summary: String { get }
    }

    public struct Value: Payload {
        public let summary: String

        public init(summary: String) {
            self.summary = summary
        }
    }
}

public protocol NestedPayloadReporter {
    func report(_ payload: any NestedPayloadNamespace.Payload) -> String
}

public enum ExternalAPI {
    public struct Envelope<Value> {
        public let value: Value

        public init(value: Value) {
            self.value = value
        }
    }
}

public protocol NestedGenericEnvelopeGateway {
    func submit(_ envelope: ExternalAPI.Envelope<ExternalReservation>) -> UInt64
}

public protocol GenericPayloadReporter {
    func report(
        _ envelope: ExternalAPI.Envelope<any ReportPayload & DetailedReportPayload>
    ) -> String
}

public struct ExternalGenericAPI<Payload> {
    public struct Status {
        public let payload: Payload

        public init(payload: Payload) {
            self.payload = payload
        }
    }

    public struct Envelope<Metadata> {
        public let payload: Payload
        public let metadata: Metadata

        public init(payload: Payload, metadata: Metadata) {
            self.payload = payload
            self.metadata = metadata
        }
    }
}

public protocol GenericNestedEnvelopeGateway {
    func submit(
        _ envelope: ExternalGenericAPI<ExternalReservation>.Envelope<String>
    ) -> UInt64
}

public protocol GenericParentStatusGateway {
    func submit(_ status: ExternalGenericAPI<ExternalReservation>.Status) -> UInt64
}

public protocol GenericParentPayloadReporter {
    func report(
        _ status: ExternalGenericAPI<any ReportPayload & DetailedReportPayload>.Status
    ) -> String
}

/// A client boundary whose non-frozen generic payload is itself an escaping
/// Swift function value, as used by configurable routing or retry policies.
public protocol GenericClosurePayloadGateway {
    func submit(
        _ status: ExternalGenericAPI<@Sendable (Int) -> Int>.Status
    ) -> Int
}

/// Exercises argument-location recalculation after a resilient generic value.
public protocol GenericClosurePayloadWithMarkersGateway {
    func submit(
        prefix: UInt64,
        status: ExternalGenericAPI<@Sendable (Int) -> Int>.Status,
        suffix: UInt64
    ) -> Int
}

/// A result boundary that cannot observe the caller's generic value convention.
public protocol GenericClosurePayloadSource {
    func current() -> ExternalGenericAPI<@Sendable (Int) -> Int>.Status
}

/// An async boundary combines resilient generic storage with a hidden
/// continuation argument in the witness ABI.
public protocol AsyncGenericClosurePayloadGateway {
    func submit(
        _ status: ExternalGenericAPI<@Sendable (Int) -> Int>.Status
    ) async -> Int
}

/// A frozen generic control proves that calibration keeps the caller's direct
/// convention when the generic declaration does publish that guarantee.
@frozen public struct FrozenExternalGenericBox<Value> {
    public let value: Value

    public init(value: Value) {
        self.value = value
    }
}

public protocol FrozenGenericClosurePayloadGateway {
    func submit(_ box: FrozenExternalGenericBox<@Sendable (Int) -> Int>) -> Int
}

/// A resilient generic enum mirrors a state-machine payload from a framework
/// rather than a struct model.
public enum ExternalGenericChoice<Payload> {
    case value(Payload)
    case unavailable
}

public protocol GenericClosureChoiceGateway {
    func submit(_ choice: ExternalGenericChoice<@Sendable (Int) -> Int>) -> Int
}

public struct OrderedExternalAPI<Payload: Comparable> {
    public struct Status {
        public let payload: Payload

        public init(payload: Payload) {
            self.payload = payload
        }
    }
}

public protocol OrderedGenericParentStatusGateway {
    func submit(_ status: OrderedExternalAPI<ExternalReservation>.Status) -> UInt64
}

public protocol ByteReader {
    func read(_ pointer: UnsafePointer<UInt8>) -> UInt8
}

public protocol ByteBufferReader {
    func sum(_ buffer: UnsafeBufferPointer<UInt8>) -> UInt
}

public protocol ValueTransformer {
    func transform(
        _ transformer: @escaping @Sendable (Int) -> Int,
        value: Int
    ) -> Int
}

public protocol TrailingValueTransformer {
    func transform(
        _ value: Int,
        using transformer: @escaping @Sendable (Int) -> Int
    ) -> Int
}

public protocol AsyncValueTransformer {
    func transform(
        _ transformer: @escaping @Sendable (Int) async -> Int,
        value: Int
    ) async -> Int
}

public typealias CIntTransformer = @convention(c) (Int32) -> Int32

public protocol CValueTransformer {
    func transform(
        _ transformer: @escaping CIntTransformer,
        value: Int32
    ) -> Int32
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

    public func sum(_ values: ArraySlice<Int>) -> Int {
        values.reduce(0, +)
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

public struct LiveImportedDataSource: ImportedDataSource {
    public init() {}

    public func loadData() async throws -> Data {
        Data([1, 2, 3])
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct LiveCommonFoundationResultSource: CommonFoundationResultSource {
    public init() {}

    public var currentURL: URL { URL(fileURLWithPath: "/live") }
    public func data() -> Data { Data() }
    public func date() throws -> Date { Date(timeIntervalSinceReferenceDate: 0) }
    public func identifier() async -> UUID { UUID() }
    public func interval() async throws -> DateInterval {
        DateInterval(start: Date(timeIntervalSinceReferenceDate: 0), duration: 1)
    }
    public func calendar() async throws -> Calendar { Calendar(identifier: .gregorian) }
    public func locale() -> Locale { Locale(identifier: "en_US_POSIX") }
    public func timeZone() throws -> TimeZone { TimeZone(secondsFromGMT: 0)! }
    public func indexPath() async -> IndexPath { IndexPath(index: 0) }
    public func indexSet() async throws -> IndexSet { IndexSet(integer: 0) }
    public func characterSet() -> CharacterSet { CharacterSet(charactersIn: "A") }
    public func decimal() throws -> Decimal { Decimal(1) }
    public func notificationName() async -> Notification.Name {
        Notification.Name("live")
    }
    public func notification() async throws -> Notification {
        Notification(name: Notification.Name("live"))
    }
    public func attributedString() -> AttributedString { AttributedString("live") }
    public func personNameComponents() async throws -> PersonNameComponents {
        PersonNameComponents()
    }
    #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
        public func request() async throws -> URLRequest {
            URLRequest(url: URL(fileURLWithPath: "/live"))
        }
    #endif
}

public struct LiveParameterizedFoundationResultSource: ParameterizedFoundationResultSource {
    public init() {}

    public func identifier(for value: Int, namespace: String) async -> UUID {
        UUID()
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
