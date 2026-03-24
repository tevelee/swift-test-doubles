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
