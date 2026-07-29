protocol ManualStubGeneratorSample {
    func fetch(_ value: Int) -> String
    func delayed(_ value: Int) async -> String
    var label: String { get set }
    subscript(_ value: Int) -> String { get set }
}
