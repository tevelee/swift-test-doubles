import Testing
@testable import TestDoubles

// Class-typed values cannot be synthesized as recording placeholders, so
// each test exercises the registry with its own class to stay independent
// of parallel tests sharing the process-global registry.
final class PlaceholderArgumentUser: @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name }
}

final class PlaceholderResultUser: @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name }
}

final class PlaceholderPrecedenceUser: @unchecked Sendable {
    let name: String
    init(name: String) { self.name = name }
}

// Internal, not private: the conformers double as automatic-discovery
// fixtures, whose conformance records must stay reachable in release builds.
protocol PlaceholderRegistryDirectory {
    func displayName(for user: PlaceholderArgumentUser) -> String
    func currentUser() -> PlaceholderResultUser
    func badge(for user: PlaceholderPrecedenceUser) -> String
}

struct RealPlaceholderRegistryDirectory: PlaceholderRegistryDirectory {
    func displayName(for user: PlaceholderArgumentUser) -> String { user.name }
    func currentUser() -> PlaceholderResultUser { PlaceholderResultUser(name: "real") }
    func badge(for user: PlaceholderPrecedenceUser) -> String { user.name }
}

@Suite struct PlaceholderRegistryTests {
    @Test func registeredFactorySuppliesArgumentRecordingValues() throws {
        RecordingPlaceholders.register { PlaceholderArgumentUser(name: "recording") }
        defer { RecordingPlaceholders.unregister(PlaceholderArgumentUser.self) }

        let stub = try Stub<any PlaceholderRegistryDirectory>()
        // Without the registration, any() would halt: a class placeholder
        // cannot be synthesized and would need any(using:).
        stub.when { $0.displayName(for: any()) }.thenReturn("stubbed")

        let directory: any PlaceholderRegistryDirectory = stub()
        #expect(directory.displayName(for: PlaceholderArgumentUser(name: "eve")) == "stubbed")
    }

    @Test func registeredFactorySuppliesReturnRecordingValues() throws {
        RecordingPlaceholders.register { PlaceholderResultUser(name: "recording") }
        defer { RecordingPlaceholders.unregister(PlaceholderResultUser.self) }

        let stub = try Stub<any PlaceholderRegistryDirectory>()
        let configured = PlaceholderResultUser(name: "configured")
        // Without the registration, recording currentUser() would halt and
        // need the returning: overload.
        stub.when { $0.currentUser() }.thenReturn(configured)

        let directory: any PlaceholderRegistryDirectory = stub()
        #expect(directory.currentUser() === configured)
    }

    @Test func explicitUsingValueWinsOverTheRegisteredFactory() throws {
        let counter = LockedCounter()
        RecordingPlaceholders.register {
            counter.increment()
            return PlaceholderPrecedenceUser(name: "registered")
        }
        defer { RecordingPlaceholders.unregister(PlaceholderPrecedenceUser.self) }

        let stub = try Stub<any PlaceholderRegistryDirectory>()
        stub.when { $0.badge(for: any(using: PlaceholderPrecedenceUser(name: "explicit"))) }
            .thenReturn("stubbed")

        let directory: any PlaceholderRegistryDirectory = stub()
        #expect(directory.badge(for: PlaceholderPrecedenceUser(name: "eve")) == "stubbed")
        #expect(counter.value == 0)
    }
}
