public struct ExternalUserID: Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct ExternalUserProfile: Equatable, Sendable {
    public let id: ExternalUserID
    public let name: String
    public let age: Int
    public let isActive: Bool

    public init(
        id: ExternalUserID,
        name: String,
        age: Int,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.isActive = isActive
    }
}

public enum ExternalRepositoryError: Error, Equatable {
    case unavailable
}

public protocol ExternalUserRepository: Sendable {
    var cachedUserCount: Int { get }

    func cachedUser(id: ExternalUserID) -> ExternalUserProfile?
    func remove(id: ExternalUserID, force: Bool) throws -> Bool
    func save(_ profile: ExternalUserProfile) async throws
    func search(
        query: String,
        page: Int,
        pageSize: Int,
        includeInactive: Bool
    ) async throws -> [ExternalUserProfile]
}

public struct RealExternalUserRepository: ExternalUserRepository {
    public init() {}

    public var cachedUserCount: Int { 0 }

    public func cachedUser(id: ExternalUserID) -> ExternalUserProfile? {
        nil
    }

    public func remove(id: ExternalUserID, force: Bool) throws -> Bool {
        false
    }

    public func save(_ profile: ExternalUserProfile) async throws {}

    public func search(
        query: String,
        page: Int,
        pageSize: Int,
        includeInactive: Bool
    ) async throws -> [ExternalUserProfile] {
        []
    }
}
