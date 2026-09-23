protocol BuildGeneratedGreetingService {
    func greeting(for name: String) -> String
    var requestCount: Int { get }
}

enum BuildGeneratedGetterFailure: Error, Equatable {
    case rejected
}

protocol BuildGeneratedEffectfulGetters {
    var asyncValue: Int { get async }
    var throwingValue: Int { get throws }
    var asyncThrowingValue: Int { get async throws }
    var typedThrowingValue: Int { get throws(BuildGeneratedGetterFailure) }
    var asyncTypedThrowingValue: Int { get async throws(BuildGeneratedGetterFailure) }
    subscript(asynchronous index: Int) -> Int { get async }
    subscript(throwing index: Int) -> Int { get throws }
    subscript(asyncThrowing index: Int) -> Int { get async throws }
    subscript(typedThrowing index: Int) -> Int { get throws(BuildGeneratedGetterFailure) }
    subscript(asyncTypedThrowing index: Int) -> Int { get async throws(BuildGeneratedGetterFailure) }
}

protocol BuildGeneratedDelegate: AnyObject {
    func didFinish(text: String)
}

protocol BuildGeneratedDetailDelegate: BuildGeneratedDelegate {
    func didCancel()
}

@MainActor
protocol BuildGeneratedRouter {
    func push(_ screen: String)
    func present(title: String) async -> Bool
    var depth: Int { get }
}

protocol BuildGeneratedCache<Key, Value> {
    associatedtype Key: Hashable
    associatedtype Value
    func value(for key: Key) -> Value?
    func store(_ value: Value, for key: Key)
}

enum BuildGeneratedLogLevel: Int, Sendable {
    case info
    case error
}

protocol BuildGeneratedLogger {
    func log(
        _ level: BuildGeneratedLogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        line: Int
    )
}

protocol BuildGeneratedTransformer {
    func map(_ values: [Int], transform: (Int) -> Int) -> [Int]
    func tryMap(_ values: [Int], transform: (Int) throws -> Int) rethrows -> [Int]
    func load(_ path: String, completion: @escaping (Result<Int, any Error>) -> Void)
    func visit(_ body: (inout Int) -> Void) -> Int
    func perform(_ work: @Sendable () async -> Void) async
}

protocol BuildGeneratedAggregator {
    func sum(_ numbers: some Sequence<Int>) -> Int
}
