protocol BuildGeneratedGreetingService {
    func greeting(for name: String) -> String
    var requestCount: Int { get }
}
