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

protocol InitializerSpyService {
    init(value: Int)
    func value() -> Int
}

struct RealInitializerSpyService: InitializerSpyService {
    let storedValue: Int

    init(value: Int) {
        storedValue = value
    }

    func value() -> Int { storedValue }
}

// Fifteen arguments overflow even the widest architecture's register budget
// (arm64: 8 argument registers) by more than the outgoing-stack-spill ceiling
// (8 words, shared with the target's own spilled metadata/witness table -- see
// SyncStackSpySpillForwardingTests) can absorb on every supported architecture.
protocol WideSpyService {
    // swiftlint:disable:next function_parameter_count
    func combine(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int,
        _ ninth: Int,
        _ tenth: Int,
        _ eleventh: Int,
        _ twelfth: Int,
        _ thirteenth: Int,
        _ fourteenth: Int,
        _ fifteenth: Int
    ) -> Int
}

struct RealWideSpyService: WideSpyService {
    // swiftlint:disable:next function_parameter_count
    func combine(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int,
        _ ninth: Int,
        _ tenth: Int,
        _ eleventh: Int,
        _ twelfth: Int,
        _ thirteenth: Int,
        _ fourteenth: Int,
        _ fifteenth: Int
    ) -> Int {
        first + second + third + fourth + fifth + sixth + seventh + eighth
            + ninth + tenth + eleventh + twelfth + thirteenth + fourteenth
            + fifteenth
    }
}

protocol DynamicSelfSpyService {
    func duplicate() -> Self
}

struct RealDynamicSelfSpyService: DynamicSelfSpyService {
    func duplicate() -> Self { self }
}

protocol FunctionValueSpyService {
    func transform(_ operation: @escaping (Int) -> Int) -> (Int) -> Int
}

struct RealFunctionValueSpyService: FunctionValueSpyService {
    func transform(_ operation: @escaping (Int) -> Int) -> (Int) -> Int {
        operation
    }
}

@Suite struct SpyTests {
    @Test func factoryForwardsUnmatchedCallsAndRecordsThem() {
        let target = RealSpyService()
        let spy: Spy<any SpyService> = Spy.make(forwardingTo: target)
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

        spy.verify(.exactly(2)) { $0.fetch(id: Match.any()) }
    }

    @Test func forwardedInvocationsExcludeOverridesAndKeepArgumentsTyped() throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        spy.when { $0.fetch(id: 1) }.thenReturn("overridden")
        let fetches = spy.when { $0.fetch(id: Match.any()) }
        let service: any SpyService = spy()

        #expect(service.fetch(id: 1) == "overridden")
        #expect(service.fetch(id: 2) == "real:2")
        #expect(service.fetch(id: 3) == "real:3")

        let forwarded: [Int] = fetches.forwarded.arguments()
        #expect(forwarded == [2, 3])
    }

    @Test func callPatternComposesForwardedInteractions() throws {
        let real = RealSpyService()
        let spy: Spy<any SpyService> = .make(forwardingTo: real)
        let pattern = spy.when { $0.fetch(id: Match.any()) }
        spy.when { $0.fetch(id: Match.equal(1)) }.thenReturn("override")
        let service: any SpyService = spy()

        #expect(service.fetch(id: 1) == "override")
        #expect(service.fetch(id: 2) == "real:2")
        #expect(pattern.callCount == 2)
        #expect(pattern.stubbed.callCount == 1)
        #expect(pattern.forwarded.callCount == 1)
        #expect(pattern.forwarded.wasCalled)
        pattern.stubbed.verify()
        pattern.forwarded.verify()
        let stubbed: [Int] = pattern.stubbed.arguments()
        let forwarded: [Int] = pattern.forwarded.arguments()
        #expect(stubbed == [1])
        #expect(forwarded == [2])

        let order = InvocationOrder()
        order.verify(pattern.stubbed)
        order.verify(pattern.forwarded)
    }

    @Test func forwardsThrowingRequirements() throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        let service: any SpyService = spy()

        #expect(try service.load(path: "readme") == "contents:readme")
        #expect(throws: SpyServiceError.missing("missing")) {
            try service.load(path: "missing")
        }
        spy.verify(.exactly(2)) { try $0.load(path: Match.any()) }
    }

    @Test func forwardsAsyncRequirementsAndSupportsOverrides() async throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        await spy.when { try await $0.fetchLater(id: 1) }
            .thenReturn("overridden-later")

        let service: any SpyService = spy()
        #expect(try await service.fetchLater(id: 1) == "overridden-later")
        #expect(try await service.fetchLater(id: 2) == "later:2")
        await spy.verify(.exactly(2)) { try await $0.fetchLater(id: Match.any()) }
    }

    @Test func forwardedInvocationsSupportAsyncRequirements() async throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        await spy.when { try await $0.fetchLater(id: 1) }
            .thenReturn("overridden-later")
        let fetches = await spy.when { try await $0.fetchLater(id: Match.any()) }
        let service: any SpyService = spy()

        _ = try await service.fetchLater(id: 1)
        _ = try await service.fetchLater(id: 2)

        let forwarded: [Int] = fetches.forwarded.arguments()
        #expect(forwarded == [2])
    }

    @Test func forwardedPatternStreamsAndEventuallyVerifiesDelegatedCalls() async throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        spy.when { $0.fetch(id: 1) }.thenReturn("overridden")
        let fetches = spy.when { $0.fetch(id: Match.any()) }
        let stream: InvocationStream<Int> = fetches.forwarded.stream()
        let nextForwarded = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        let verification = Task {
            await fetches.forwarded.verify(2..., within: .seconds(1))
        }
        let service: any SpyService = spy()

        _ = service.fetch(id: 1)
        _ = service.fetch(id: 2)
        _ = service.fetch(id: 3)

        #expect(await nextForwarded.value == 2)
        await verification.value
        #expect(fetches.forwarded.callCount == 2)
    }

    @Test func forwardedPatternVerificationSupportsManualClocks() async throws {
        let spy = try Spy<any SpyService>(forwardingTo: RealSpyService())
        spy.when { $0.fetch(id: 1) }.thenReturn("overridden")
        let fetches = spy.when { $0.fetch(id: Match.any()) }
        let service: any SpyService = spy()
        let clock = ManualStubClock()
        let verification = Task {
            await fetches.forwarded.verify(
                1...,
                within: .seconds(1),
                using: clock
            )
        }

        await clock.waitForSleepers(atLeast: 1)
        _ = service.fetch(id: 1)
        await Task.yield()
        #expect(fetches.forwarded.callCount == 0)
        #expect(clock.pendingSleepCount == 1)

        _ = service.fetch(id: 2)
        await verification.value
        #expect(clock.pendingSleepCount == 0)
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

    @Test func forwardsStaticRequirements() throws {
        let spy = try Spy<any StaticSpyService>(forwardingTo: RealStaticSpyService())

        #expect(spy.withValue { type(of: $0).value() } == 1)
        spy.verify { type(of: $0).value() }
    }

    @Test func permitsExplicitInitializerOverrides() throws {
        let spy = try Spy<any InitializerSpyService>(
            forwardingTo: RealInitializerSpyService(value: 0)
        )
        spy.when(initializer: { type(of: $0).init(value: Match.any()) }).thenInitialize()
        spy.when { $0.value() }.thenReturn(42)

        let seed: any InitializerSpyService = spy()
        let initialized = type(of: seed).init(value: 7)
        #expect(initialized.value() == 42)
        spy.verify { type(of: $0).init(value: Match.equal(7)) }
    }

    @Test func rejectsArgumentsThatCannotPreserveTheOriginalStack() {
        let error = #expect(throws: StubError.self) {
            _ = try Spy<any WideSpyService>(forwardingTo: RealWideSpyService())
        }
        #expect(
            error?.description.contains(
                "needs more outgoing stack transport"
            ) == true
        )
    }

    @Test func rejectsDynamicSelfResultsAtConstruction() {
        let error = #expect(throws: StubError.self) {
            _ = try Spy<any DynamicSelfSpyService>(
                forwardingTo: RealDynamicSelfSpyService()
            )
        }
        #expect(
            error?.description.contains(
                "does not yet support dynamic Self results"
            ) == true
        )
    }

    @Test func rejectsFunctionValuesAtConstruction() {
        let error = #expect(throws: StubError.self) {
            _ = try Spy<any FunctionValueSpyService>(
                forwardingTo: RealFunctionValueSpyService()
            )
        }
        #expect(
            error?.description.contains(
                "does not yet support function-valued arguments or results"
            ) == true
        )
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct SpyFactoryExitTests {
        @Test func concreteTargetInferenceFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = Spy.make(forwardingTo: RealSpyService())
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("Could not construct a spy"))
            #expect(diagnostic.contains("RealSpyService"))
            #expect(diagnostic.contains("protocol existential"))
        }
    }
#endif
