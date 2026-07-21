public protocol ThrowingFileService {
    func read(path: String) throws -> String
    func write(path: String, content: String) throws
}

public struct RealFileService: ThrowingFileService {
    public init() {}
    public func read(path: String) throws -> String { "" }
    public func write(path: String, content: String) throws {}
}

public protocol AsyncDataLoader: Sendable {
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

public typealias ExternalTransform = @Sendable (Int) -> Int
public typealias ExternalFormatter = (Int) -> Int

/// Compiled in a separate module so automatic closure support cannot depend on
/// access to the protocol declaration's source or on attached annotations.
public protocol ExternalClosureService {
    func transform(_ body: @escaping ExternalTransform) -> ExternalTransform
    func apply(_ body: @escaping ExternalTransform, to value: Int) -> Int
    var formatter: ExternalFormatter { get }
}

public struct RealExternalClosureService: ExternalClosureService {
    public init() {}
    public func transform(_ body: @escaping ExternalTransform) -> ExternalTransform { body }
    public func apply(_ body: @escaping ExternalTransform, to value: Int) -> Int { body(value) }
    public var formatter: ExternalFormatter { { $0 } }
}

public protocol PrototypeCalculator {
    func add(_ a: Int, _ b: Int) -> Int
    func describe(_ value: Int) -> String
    var precision: Int { get }
}

public protocol UserRepository {
    func find(id: Int) -> String
}

public struct RealUserRepository: UserRepository {
    public init() {}
    public func find(id: Int) -> String { "" }
}

public protocol NotificationService {
    func send(to userId: Int, message: String) throws
}

public struct RealNotificationService: NotificationService {
    public init() {}
    public func send(to userId: Int, message: String) throws {}
}
