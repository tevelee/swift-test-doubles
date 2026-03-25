import Foundation

/// Sample protocols for testing runtime compilation.
/// These live in the TestDoubles module so the RuntimeCompiler can import them.

public protocol ThrowingFileService {
    func read(path: String) throws -> String
    func write(path: String, content: String) throws
    func exists(at path: String) -> Bool
    var basePath: String { get }
}

public struct RealFileService: ThrowingFileService {
    public init() {}
    public func read(path: String) throws -> String { "" }
    public func write(path: String, content: String) throws {}
    public func exists(at path: String) -> Bool { false }
    public var basePath: String { "/" }
}

public protocol AsyncDataLoader {
    func load(url: String) async throws -> String
    func prefetch(urls: [String]) async
    var cacheSize: Int { get }
}

public struct RealDataLoader: AsyncDataLoader {
    public init() {}
    public func load(url: String) async throws -> String { "" }
    public func prefetch(urls: [String]) async {}
    public var cacheSize: Int { 0 }
}

// MARK: - Rich protocols for showcasing

/// Repository returning custom value types and collections.
public struct User: Equatable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

public protocol UserRepository {
    func find(id: Int) -> String
    func search(query: String) -> [String]
    func save(name: String, age: Int) throws -> Bool
    func delete(id: Int) throws
    var count: Int { get }
}

public struct RealUserRepository: UserRepository {
    public init() {}
    public func find(id: Int) -> String { "" }
    public func search(query: String) -> [String] { [] }
    public func save(name: String, age: Int) throws -> Bool { false }
    public func delete(id: Int) throws {}
    public var count: Int { 0 }
}

/// A payment service with complex return types.
public struct PaymentResult: Equatable, Sendable {
    public let transactionId: String
    public let amount: Double
    public let success: Bool
    public init(transactionId: String, amount: Double, success: Bool) {
        self.transactionId = transactionId; self.amount = amount; self.success = success
    }
}

public protocol PaymentGateway {
    func charge(amount: Double, currency: String) throws -> PaymentResult
    func refund(transactionId: String) throws -> PaymentResult
    var supportedCurrencies: [String] { get }
    var isAvailable: Bool { get }
}

public struct RealPaymentGateway: PaymentGateway {
    public init() {}
    public func charge(amount: Double, currency: String) throws -> PaymentResult {
        PaymentResult(transactionId: "", amount: amount, success: false)
    }
    public func refund(transactionId: String) throws -> PaymentResult {
        PaymentResult(transactionId: transactionId, amount: 0, success: false)
    }
    public var supportedCurrencies: [String] { [] }
    public var isAvailable: Bool { false }
}

/// Notification service mixing void, throwing, and collection methods.
public protocol NotificationService {
    func send(to userId: Int, message: String) throws
    func sendBulk(to userIds: [Int], message: String) throws -> Int
    func pending(for userId: Int) -> [String]
    func markRead(notificationId: String)
    var unreadCount: Int { get }
}

public struct RealNotificationService: NotificationService {
    public init() {}
    public func send(to userId: Int, message: String) throws {}
    public func sendBulk(to userIds: [Int], message: String) throws -> Int { 0 }
    public func pending(for userId: Int) -> [String] { [] }
    public func markRead(notificationId: String) {}
    public var unreadCount: Int { 0 }
}
