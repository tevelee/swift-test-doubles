enum GeneratedManualStubFailure: Error, Equatable {
    case rejected
}

protocol GeneratedManualStubService {
    func render(_ value: Int) -> String
    func render(_ value: String) -> String
    func save(_ value: Int) throws(GeneratedManualStubFailure)
    func refresh(_ value: Int) async throws(GeneratedManualStubFailure) -> String
    var count: Int { get set }
    subscript(_ value: Int) -> String { get set }
}
