import TestDoubles
import Testing

enum SpyServiceError: Error, Equatable {
    case missing(String)
}

protocol SpyService {
    func fetch(id: Int) -> String
    func load(path: String) throws -> String
    func fetchLater(id: Int) async throws -> String
    var label: String { get }
}

final class RealSpyService: SpyService {
    private(set) var fetchedIDs: [Int] = []

    func fetch(id: Int) -> String {
        fetchedIDs.append(id)
        return "real:\(id)"
    }

    func load(path: String) throws -> String {
        guard path != "missing" else { throw SpyServiceError.missing(path) }
        return "contents:\(path)"
    }

    func fetchLater(id: Int) async throws -> String {
        "later:\(id)"
    }

    var label: String { "real-service" }
}

protocol ClassConstrainedSpyService: AnyObject {
    func nextValue() -> Int
}

final class RealClassConstrainedSpyService: ClassConstrainedSpyService {
    private var value = 0

    func nextValue() -> Int {
        value += 1
        return value
    }
}

protocol ValueSpyService {
    mutating func nextValue() -> Int
}

struct RealValueSpyService: ValueSpyService {
    private var value = 0

    mutating func nextValue() -> Int {
        value += 1
        return value
    }
}

protocol ParentSpyService {
    func parentValue() -> String
}

protocol ChildSpyService: ParentSpyService {
    func childValue() -> String
}

struct RealChildSpyService: ChildSpyService {
    func parentValue() -> String { "parent" }
    func childValue() -> String { "child" }
}

protocol AssociatedSpyService<Value> {
    associatedtype Value
    func roundTrip(_ value: Value) -> Value
}

struct RealAssociatedSpyService: AssociatedSpyService {
    func roundTrip(_ value: Int) -> Int { value }
}

protocol StaticSpyService {
    static func value() -> Int
}

struct RealStaticSpyService: StaticSpyService {
    static func value() -> Int { 1 }
}

protocol WideSpyService {
    func combine(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int
    ) -> Int
}

struct RealWideSpyService: WideSpyService {
    func combine(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int
    ) -> Int {
        first + second + third + fourth + fifth + sixth + seventh
    }
}

protocol MutableSpyService {
    var value: Int { get set }
}

struct RealMutableSpyService: MutableSpyService {
    var value = 0
}

@Suite struct SpyTests {
    @Test func factoryForwardsUnmatchedCallsAndRecordsThem() {
        let target = RealSpyService()
        let spy = makeSpy(SpyService.self, forwardingTo: target)
        let service: any SpyService = spy()

        #expect(service.fetch(id: 7) == "real:7")
        #expect(service.label == "real-service")
        #expect(target.fetchedIDs == [7])

        spy.verify { $0.fetch(id: 7) }
        spy.verify { $0.label }
    }

    @Test func matchedOverrideWinsWhileOtherArgumentsForward() throws {
        let target = RealSpyService()
        let spy = try Spy<any SpyService>(forwardingTo: target)
        spy.when { $0.fetch(id: 1) }.thenReturn("overridden")

        let service: any SpyService = spy()
        #expect(service.fetch(id: 1) == "overridden")
        #expect(service.fetch(id: 2) == "real:2")
        #expect(target.fetchedIDs == [2])

        spy.verify(.exactly(2)) { $0.fetch(id: any()) }
    }

    @Test func forwardsThrowingRequirements() throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        let service: any SpyService = spy()

        #expect(try service.load(path: "readme") == "contents:readme")
        #expect(throws: SpyServiceError.missing("missing")) {
            try service.load(path: "missing")
        }
        spy.verify(.exactly(2)) { try $0.load(path: any()) }
    }

    @Test func forwardsAsyncRequirementsAndSupportsOverrides() async throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        await spy.when { try await $0.fetchLater(id: 1) }
            .thenReturn("overridden-later")

        let service: any SpyService = spy()
        #expect(try await service.fetchLater(id: 1) == "overridden-later")
        #expect(try await service.fetchLater(id: 2) == "later:2")
        await spy.verify(.exactly(2)) { try await $0.fetchLater(id: any()) }
    }

    @Test func forwardsClassConstrainedProtocolsToTheSameObject() throws {
        let target = RealClassConstrainedSpyService()
        let spy = try Spy<any ClassConstrainedSpyService>(forwardingTo: target)
        let service: any ClassConstrainedSpyService = spy()

        #expect(service.nextValue() == 1)
        #expect(service.nextValue() == 2)
        spy.verify(.exactly(2)) { $0.nextValue() }
    }

    @Test func preservesMutationsToAnOwnedValueTarget() throws {
        let spy = try Spy<any ValueSpyService>(forwardingTo: RealValueSpyService())
        var service: any ValueSpyService = spy()

        #expect(service.nextValue() == 1)
        #expect(service.nextValue() == 2)
        spy.verify(.exactly(2)) { (service: inout any ValueSpyService) in
            _ = service.nextValue()
        }
    }

    @Test func forwardsInheritedRequirementsThroughTheirDeclaringWitnesses() throws {
        let spy = try Spy<any ChildSpyService>(forwardingTo: RealChildSpyService())
        let service: any ChildSpyService = spy()

        #expect(service.parentValue() == "parent")
        #expect(service.childValue() == "child")
        spy.verify { $0.parentValue() }
        spy.verify { $0.childValue() }
    }

    @Test func forwardsBoundAssociatedTypeValues() throws {
        let spy = try Spy<any AssociatedSpyService<Int>>(
            forwardingTo: RealAssociatedSpyService()
        )
        let service: any AssociatedSpyService<Int> = spy()

        #expect(service.roundTrip(42) == 42)
        spy.verify { $0.roundTrip(42) }
    }

    @Test func rejectsStaticRequirementsAtConstruction() {
        #expect(throws: StubError.self) {
            _ = try Spy<any StaticSpyService>(forwardingTo: RealStaticSpyService())
        }
    }

    @Test func rejectsArgumentsThatCannotPreserveTheOriginalStack() {
        #expect(throws: StubError.self) {
            _ = try Spy<any WideSpyService>(forwardingTo: RealWideSpyService())
        }
    }

    @Test func rejectsModifyCoroutinesAtConstruction() {
        #expect(throws: StubError.self) {
            _ = try Spy<any MutableSpyService>(forwardingTo: RealMutableSpyService())
        }
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct SpyFactoryExitTests {
        @Test func unsupportedProtocolShapeFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = makeSpy(
                    StaticSpyService.self,
                    forwardingTo: RealStaticSpyService()
                )
            }
            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("Could not construct a spy"))
            #expect(diagnostic.contains("StaticSpyService"))
            #expect(diagnostic.contains("supports instance requirements only"))
        }
    }
#endif
