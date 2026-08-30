import Foundation

/// Imported result tuples whose resilient Foundation leaves require the
/// client's compiler to choose their concrete result transport.
public protocol CompilerProvenFoundationTupleSource: Sendable {
    func dataAndCount() -> (Data, Int)
    func dataAndRatio() -> (Data, Double)

    #if compiler(>=6.4)
        func identifierAndCount() -> (UUID, Int)
        func identifierAndDate(for value: Int) throws -> (UUID, Date, Int)
        func nestedFoundationValues() -> (Data, (UUID, Int))
        func asyncIdentifierAndCount(for value: Int) async -> (UUID, Int)
    #endif
}

public protocol UnprovenCustomTupleResultSource: Sendable {
    func reservationAndCount() -> (ExternalReservation, Int)
}

#if compiler(>=6.4)
    public protocol ForwardingFoundationTupleSource: Sendable {
        func identifierAndCount(for value: Int) -> (UUID, Int)
    }

    public struct LiveForwardingFoundationTupleSource:
        ForwardingFoundationTupleSource
    {
        public init() {}

        public func identifierAndCount(for value: Int) -> (UUID, Int) {
            (
                UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, UInt8(value)
                    )
                ),
                value
            )
        }
    }
#endif
