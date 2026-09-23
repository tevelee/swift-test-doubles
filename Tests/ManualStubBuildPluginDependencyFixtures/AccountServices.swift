import Foundation

/// A production module that declares protocols but does not depend on
/// TestDoubles. The build plugin attached to a test target generates their
/// stubs.
public enum AccountTier: Sendable, Equatable {
    case free
    case pro(seats: Int)
}

protocol AccountService {
    func tier(for userID: Int) async throws -> AccountTier
    func rename(_ userID: Int, to name: String) throws
}

public protocol AccountClock {
    var now: Date { get }
}

private protocol AccountSecret {
    func token() -> String
}

struct LiveAccountSecret: AccountSecret {
    func token() -> String { "" }
}
