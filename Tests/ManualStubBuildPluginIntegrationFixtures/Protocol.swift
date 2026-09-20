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
