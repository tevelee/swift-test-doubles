protocol ManualStubGeneratorSample {
    init(seed: Int)
    func fetch(_ value: Int) -> String
    func delayed(_ value: Int) async -> String
    static func global(_ value: Int) -> String
    var label: String { get set }
    subscript(_ value: Int) -> String { get set }
}
