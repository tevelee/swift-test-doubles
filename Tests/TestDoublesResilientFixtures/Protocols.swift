@frozen public enum ResilientRuntimeError: Error, Equatable {
    case rejected(Int)
}

/// A library-evolution protocol with no concrete conformer anywhere in this
/// module. Its exported ABI requirement descriptors are the test fixture.
public protocol ResilientRuntimeService {
    func fetch(id: Int) throws -> String
    func load(id: Int) async throws(ResilientRuntimeError) -> String
    static func label(_ value: Int) -> String
    init(id: Int)
    var count: Int { get set }
}
