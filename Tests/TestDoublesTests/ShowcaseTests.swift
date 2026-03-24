import XCTest
import TestDoubles

// ============================================================================
// Showcase: What's possible with swift-test-doubles today
//
// Demonstrates the full API surface with realistic protocols and patterns.
// Every test here passes — this IS the current capability set.
// ============================================================================

// MARK: - Realistic Protocol Definitions

/// A typical service protocol with various method signatures.
protocol UserRepository {
    func find(id: Int) -> String
    func search(query: String) -> [String]
    func save(name: String, age: Int) -> Bool
    var count: Int { get }
}
struct RealUserRepository: UserRepository {
    func find(id: Int) -> String { "" }
    func search(query: String) -> [String] { [] }
    func save(name: String, age: Int) -> Bool { false }
    var count: Int { 0 }
}

/// Protocol with getters, setters, and void methods.
protocol Settings {
    var theme: String { get set }
    var fontSize: Int { get }
    func reset()
    func apply(key: String)
}
struct RealSettings: Settings {
    var theme: String = "light"
    var fontSize: Int { 14 }
    func reset() {}
    func apply(key: String) {}
}

/// Protocol returning collection types (uses ABI-class fallback thunks).
protocol TagStore {
    func tags(for category: String) -> [String]
    func allCategories() -> [String]
    func tagCount(in category: String) -> Int
    var isEmpty: Bool { get }
}
struct RealTagStore: TagStore {
    func tags(for category: String) -> [String] { [] }
    func allCategories() -> [String] { [] }
    func tagCount(in category: String) -> Int { 0 }
    var isEmpty: Bool { true }
}

/// Protocol with multiple getters of different types.
protocol AppConfig {
    var appName: String { get }
    var version: Int { get }
    var isDebug: Bool { get }
    var scale: Double { get }
}
struct RealAppConfig: AppConfig {
    var appName: String { "" }
    var version: Int { 0 }
    var isDebug: Bool { false }
    var scale: Double { 1.0 }
}

/// A "throws" protocol — non-throwing thunks serve throwing slots.
protocol FileLoader {
    func load(path: String) throws -> String
    func exists(path: String) -> Bool
}
struct RealFileLoader: FileLoader {
    func load(path: String) throws -> String { "" }
    func exists(path: String) -> Bool { false }
}

// ============================================================================
// MARK: - Tests
// ============================================================================

final class ShowcaseTests: XCTestCase {

    // MARK: - Zero-Config: Auto-discovered signatures

    /// Zero-config with exact argument matching.
    func testZeroConfig_ExactMatching() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: 1) }.returns("Alice")
        stub.when { $0.find(id: 2) }.returns("Bob")
        stub.when { $0.save(name: "Charlie", age: 30) }.returns(true)
        stub.when { $0.count }.returns(100)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 1), "Alice")
        XCTAssertEqual(sut.find(id: 2), "Bob")
        XCTAssertEqual(sut.save(name: "Charlie", age: 30), true)
        XCTAssertEqual(sut.count, 100)
    }

    /// Free-function matchers: any(), equal(), match().
    func testZeroConfig_Matchers() {
        let stub = RuntimeStub<any UserRepository>()

        // Specific match first, then catch-all (first matching stub wins)
        stub.when { $0.find(id: equal(42)) }.returns("The Answer")
        stub.when { $0.find(id: any()) }.returns("Unknown")
        stub.when { $0.save(name: any(), age: any()) }.returns(false)
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 42), "The Answer")
        XCTAssertEqual(sut.find(id: 99), "Unknown")
        XCTAssertEqual(sut.save(name: "anyone", age: 0), false)
    }

    /// Predicate matcher: match() with custom logic.
    func testZeroConfig_PredicateMatcher() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: match { $0 > 100 }) }.returns("VIP")
        stub.when { $0.find(id: match { $0 <= 100 }) }.returns("Regular")
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 101), "VIP")
        XCTAssertEqual(sut.find(id: 50), "Regular")
    }

    /// Dynamic answers — compute return values based on arguments.
    func testZeroConfig_DynamicAnswers() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: any()) }.answers { args in
            let id = args[0] as! Int
            return "User_\(id)"
        }
        stub.when { $0.save(name: any(), age: any()) }.answers { args in
            let age = args[1] as! Int
            return age >= 18
        }
        stub.when { $0.count }.returns(42)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 7), "User_7")
        XCTAssertEqual(sut.find(id: 99), "User_99")
        XCTAssertEqual(sut.save(name: "Alice", age: 25), true)
        XCTAssertEqual(sut.save(name: "Bob", age: 12), false)
    }

    // MARK: - Verification

    /// Verify call counts with various styles.
    func testVerification_CallCounts() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()
        _ = sut.find(id: 1)
        _ = sut.find(id: 2)
        _ = sut.find(id: 3)
        _ = sut.count

        // Concise verify
        stub.verify(called: 3) { $0.find(id: any()) }
        stub.verify(called: 1) { $0.count }

        // Builder-style verify
        stub.verify { $0.find(id: 1) }.wasCalled()
        stub.verify { $0.find(id: any()) }.wasCalled(times: 3)

        // Never-called
        stub.verify(never: { $0.save(name: any(), age: any()) })
    }

    // MARK: - Getters, Setters, and Void Methods

    /// Setters with the `when(setting:)` API.
    func testSetters() {
        let stub = RuntimeStub<any Settings>()

        stub.when { $0.theme }.returns("dark")
        stub.when { $0.fontSize }.returns(16)
        stub.when(setting: { $0.theme = "light" })
        stub.when { $0.reset() }
        stub.when { $0.apply(key: any()) }

        let sut: any Settings = stub()
        XCTAssertEqual(sut.theme, "dark")
        XCTAssertEqual(sut.fontSize, 16)

        // Call setter
        var mutable: any Settings = stub()
        mutable.theme = "light"

        // Call void methods
        sut.reset()
        sut.apply(key: "color")

        // Verify all
        stub.verify(setting: { $0.theme = "light" }).wasCalled()
        stub.verify { $0.reset() }.wasCalled(times: 1)
        stub.verify { $0.apply(key: "color") }.wasCalled()
    }

    /// Multiple getters of different types.
    func testMultipleGetterTypes() {
        let stub = RuntimeStub<any AppConfig>()

        stub.when { $0.appName }.returns("TestApp")
        stub.when { $0.version }.returns(42)
        stub.when { $0.isDebug }.returns(true)
        stub.when { $0.scale }.returns(2.0)

        let sut: any AppConfig = stub()

        XCTAssertEqual(sut.appName, "TestApp")
        XCTAssertEqual(sut.version, 42)
        XCTAssertEqual(sut.isDebug, true)
        XCTAssertEqual(sut.scale, 2.0)
    }

    // MARK: - Collection Return Types (ABI-class fallback)

    /// Array return types via ABI-class thunks — no per-type thunks needed.
    func testCollectionReturns() {
        let stub = RuntimeStub<any TagStore>()

        stub.when { $0.tags(for: "swift") }.returns(["concurrency", "generics", "macros"])
        stub.when { $0.tags(for: any()) }.returns([])
        stub.when { $0.allCategories() }.returns(["swift", "kotlin", "rust"])
        stub.when { $0.tagCount(in: any()) }.returns(5)
        stub.when { $0.isEmpty }.returns(false)

        let sut: any TagStore = stub()

        XCTAssertEqual(sut.tags(for: "swift"), ["concurrency", "generics", "macros"])
        XCTAssertEqual(sut.tags(for: "unknown"), [])
        XCTAssertEqual(sut.allCategories(), ["swift", "kotlin", "rust"])
        XCTAssertEqual(sut.tagCount(in: "swift"), 5)
        XCTAssertEqual(sut.isEmpty, false)
    }

    // NOTE: Throwing methods work at the witness table level (non-throwing thunks
    // serve throwing slots), but the `when` recording API needs a throwing overload
    // to properly capture the call. This is a known area for improvement.

    // MARK: - Slot-Based Init (explicit signatures)

    /// When zero-config isn't available, provide slot signatures manually.
    func testSlotBasedInit() {
        let stub = RuntimeStub<any UserRepository>(
            .method(Int.self, returns: String.self),            // find(id:)
            .method(String.self, returns: String.self),         // search(query:) — note: returns [String] but String thunk used
            .method(String.self, Int.self, returns: Bool.self), // save(name:age:)
            .getter(Int.self)                                    // count
        )

        stub.when { $0.find(id: 1) }.returns("Manual")
        stub.when { $0.count }.returns(7)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 1), "Manual")
        XCTAssertEqual(sut.count, 7)
    }

    // MARK: - Side Effects

    /// Verify call history through the recorder's call log.
    func testCallLog() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()
        _ = sut.find(id: 1)
        _ = sut.find(id: 2)
        _ = sut.count

        // Access raw call log
        XCTAssertEqual(stub.calls.count, 3)
    }

    // MARK: - Multiple Stubs Coexisting

    /// Multiple independent stubs for different protocols.
    func testMultipleStubs() {
        let repoStub = RuntimeStub<any UserRepository>()
        let configStub = RuntimeStub<any AppConfig>()

        repoStub.when { $0.find(id: any()) }.returns("User")
        repoStub.when { $0.count }.returns(10)

        configStub.when { $0.appName }.returns("Test")
        configStub.when { $0.version }.returns(1)
        configStub.when { $0.isDebug }.returns(false)
        configStub.when { $0.scale }.returns(1.0)

        let repo: any UserRepository = repoStub()
        let config: any AppConfig = configStub()

        XCTAssertEqual(repo.find(id: 1), "User")
        XCTAssertEqual(repo.count, 10)
        XCTAssertEqual(config.appName, "Test")
        XCTAssertEqual(config.version, 1)
    }
}
