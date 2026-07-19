import Foundation
import Testing
import TestDoubles

struct SpyMixedAggregate: Equatable, Sendable {
    let count: Int
    let ratio: Double
}

struct SpyIndirectResult: Equatable, Sendable {
    let first: Int
    let second: Int
    let third: Int
    let fourth: Int
    let fifth: Int
}

enum SpyForwardingError: Error, Equatable {
    case rejected(Int)
}

enum SpyTypedForwardingError: Error, Equatable {
    case rejected(code: Int, message: String)
}

protocol SpyForwardingMatrixService {
    func mixed(
        floating: Double,
        scalar: Float,
        aggregate: SpyMixedAggregate
    ) -> SpyMixedAggregate
    func indirect(_ seed: Int) -> SpyIndirectResult
    func indirectLater(_ seed: Int) async -> SpyIndirectResult
    func throwing(_ value: Int) throws -> SpyMixedAggregate
    func throwingLater(_ value: Int) async throws -> SpyIndirectResult
    func typed(_ value: Int) throws(SpyTypedForwardingError) -> Int
    func typedLater(_ value: Int) async throws(SpyTypedForwardingError) -> Int
}

struct RealSpyForwardingMatrixService: SpyForwardingMatrixService {
    func mixed(
        floating: Double,
        scalar: Float,
        aggregate: SpyMixedAggregate
    ) -> SpyMixedAggregate {
        SpyMixedAggregate(
            count: aggregate.count + Int(scalar),
            ratio: aggregate.ratio + floating
        )
    }

    func indirect(_ seed: Int) -> SpyIndirectResult {
        makeIndirectResult(seed)
    }

    func indirectLater(_ seed: Int) async -> SpyIndirectResult {
        makeIndirectResult(seed)
    }

    func throwing(_ value: Int) throws -> SpyMixedAggregate {
        guard value >= 0 else { throw SpyForwardingError.rejected(value) }
        return SpyMixedAggregate(count: value, ratio: Double(value) / 2)
    }

    func throwingLater(_ value: Int) async throws -> SpyIndirectResult {
        guard value >= 0 else { throw SpyForwardingError.rejected(value) }
        return makeIndirectResult(value)
    }

    func typed(_ value: Int) throws(SpyTypedForwardingError) -> Int {
        guard value >= 0 else {
            throw .rejected(code: value, message: "sync")
        }
        return value * 2
    }

    func typedLater(_ value: Int) async throws(SpyTypedForwardingError) -> Int {
        guard value >= 0 else {
            throw .rejected(code: value, message: "async")
        }
        return value * 3
    }

    private func makeIndirectResult(_ seed: Int) -> SpyIndirectResult {
        SpyIndirectResult(
            first: seed,
            second: seed + 1,
            third: seed + 2,
            fourth: seed + 3,
            fifth: seed + 4
        )
    }
}

protocol SpySequencingService: Sendable {
    func value(for id: Int) -> String
}

final class RealSpySequencingService: SpySequencingService, @unchecked Sendable {
    private let lock = NSLock()
    private var storedIDs: [Int] = []

    var receivedIDs: [Int] {
        lock.withLock { storedIDs }
    }

    func value(for id: Int) -> String {
        lock.withLock { storedIDs.append(id) }
        return "real:\(id)"
    }
}

final class SpyLifetimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

protocol OpaqueLifetimeSpyService {
    func nextValue() -> Int
}

struct RealOpaqueLifetimeSpyService: OpaqueLifetimeSpyService {
    let state: SpyLifetimeState

    func nextValue() -> Int {
        state.next()
    }
}

protocol ClassLifetimeSpyService: AnyObject {
    func nextValue() -> Int
}

final class RealClassLifetimeSpyService: ClassLifetimeSpyService {
    let state = SpyLifetimeState()

    func nextValue() -> Int {
        state.next()
    }
}

final class SpyGetterAccessState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAccesses: [String] = []

    var accesses: [String] {
        lock.withLock { storedAccesses }
    }

    func record(_ access: String) {
        lock.withLock { storedAccesses.append(access) }
    }
}

protocol SpyGetterService {
    var throwingValue: String { get throws }
    var asyncValue: Int { get async }
    var asyncThrowingValue: String { get async throws }
}

struct RealSpyGetterService: SpyGetterService {
    let state: SpyGetterAccessState

    var throwingValue: String {
        get throws {
            state.record("throwing")
            return "forwarded"
        }
    }

    var asyncValue: Int {
        get async {
            state.record("async")
            return 42
        }
    }

    var asyncThrowingValue: String {
        get async throws {
            state.record("async-throwing")
            return "async-forwarded"
        }
    }
}

@Suite struct SpyForwardingCoverageTests {
    @Test func forwardsFloatingPointAndMixedAggregateArgumentsAndResult() throws {
        let spy = try Spy<any SpyForwardingMatrixService>(
            forwardingTo: RealSpyForwardingMatrixService()
        )
        let service: any SpyForwardingMatrixService = spy()

        let result = service.mixed(
            floating: 1.25,
            scalar: 2.0,
            aggregate: SpyMixedAggregate(count: 7, ratio: 0.5)
        )

        #expect(result == SpyMixedAggregate(count: 9, ratio: 1.75))
        spy.verify {
            $0.mixed(
                floating: equal(1.25),
                scalar: equal(2.0),
                aggregate: equal(SpyMixedAggregate(count: 7, ratio: 0.5))
            )
        }
    }

    @Test func forwardsIndirectSyncAndAsyncResults() async throws {
        let spy = try Spy<any SpyForwardingMatrixService>(
            forwardingTo: RealSpyForwardingMatrixService()
        )
        let service: any SpyForwardingMatrixService = spy()

        #expect(
            service.indirect(10)
                == SpyIndirectResult(
                    first: 10,
                    second: 11,
                    third: 12,
                    fourth: 13,
                    fifth: 14
                )
        )
        #expect(
            await service.indirectLater(20)
                == SpyIndirectResult(
                    first: 20,
                    second: 21,
                    third: 22,
                    fourth: 23,
                    fifth: 24
                )
        )
    }

    @Test func forwardsOrdinaryThrowingAndAsyncThrowingEffects() async throws {
        let spy = try Spy<any SpyForwardingMatrixService>(
            forwardingTo: RealSpyForwardingMatrixService()
        )
        let service: any SpyForwardingMatrixService = spy()

        #expect(
            try service.throwing(4)
                == SpyMixedAggregate(count: 4, ratio: 2)
        )
        let syncError = #expect(throws: SpyForwardingError.self) {
            _ = try service.throwing(-4)
        }
        #expect(syncError == .rejected(-4))

        #expect(try await service.throwingLater(5).first == 5)
        let asyncError = await #expect(throws: SpyForwardingError.self) {
            _ = try await service.throwingLater(-5)
        }
        #expect(asyncError == .rejected(-5))
    }

    @Test func forwardsTypedErrorsSynchronouslyAndAsynchronously() async throws {
        let spy = try Spy<any SpyForwardingMatrixService>(
            forwardingTo: RealSpyForwardingMatrixService()
        )
        let service: any SpyForwardingMatrixService = spy()

        #expect(try service.typed(6) == 12)
        let syncError = #expect(throws: SpyTypedForwardingError.self) {
            _ = try service.typed(-6)
        }
        #expect(syncError == .rejected(code: -6, message: "sync"))

        #expect(try await service.typedLater(7) == 21)
        let asyncError = await #expect(throws: SpyTypedForwardingError.self) {
            _ = try await service.typedLater(-7)
        }
        #expect(asyncError == .rejected(code: -7, message: "async"))
    }

    @Test func overrideThenForwardPreservesInvocationOrder() throws {
        let target = RealSpySequencingService()
        let spy = try Spy<any SpySequencingService>(forwardingTo: target)
        spy.when { $0.value(for: equal(1)) }.thenReturn("overridden")
        let service: any SpySequencingService = spy(sendability: .unchecked)

        #expect(service.value(for: 1) == "overridden")
        #expect(service.value(for: 2) == "real:2")
        #expect(target.receivedIDs == [2])
        spy.verifyInOrder {
            _ = $0.value(for: equal(1))
            _ = $0.value(for: equal(2))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func eventualVerificationObservesAForwardedCall() async throws {
        let target = RealSpySequencingService()
        let spy = try Spy<any SpySequencingService>(forwardingTo: target)
        let service: any SpySequencingService = spy(sendability: .unchecked)

        let invocation = Task {
            try await Task.sleep(for: .milliseconds(10))
            return service.value(for: 9)
        }

        await spy.verify(within: .seconds(60)) { $0.value(for: equal(9)) }
        #expect(try await invocation.value == "real:9")
        #expect(target.receivedIDs == [9])
    }

    @Test func opaqueTargetRetainsItsStateForTheSpyLifetime() throws {
        weak var weakState: SpyLifetimeState?
        var spy: Spy<any OpaqueLifetimeSpyService>?

        do {
            let state = SpyLifetimeState()
            weakState = state
            let target: any OpaqueLifetimeSpyService =
                RealOpaqueLifetimeSpyService(state: state)
            spy = try Spy(forwardingTo: target)
        }

        #expect(weakState != nil)
        do {
            let retainedSpy = try #require(spy)
            let service: any OpaqueLifetimeSpyService = retainedSpy()
            #expect(service.nextValue() == 1)
            #expect(service.nextValue() == 2)
        }
        spy = nil
        #expect(weakState == nil)
    }

    @Test func classConstrainedTargetRetainsIdentityAndStateForTheSpyLifetime() throws {
        weak var weakTarget: RealClassLifetimeSpyService?
        var spy: Spy<any ClassLifetimeSpyService>?

        do {
            let target = RealClassLifetimeSpyService()
            weakTarget = target
            spy = try Spy(forwardingTo: target as any ClassLifetimeSpyService)
        }

        #expect(weakTarget != nil)
        do {
            let retainedSpy = try #require(spy)
            let service: any ClassLifetimeSpyService = retainedSpy()
            #expect(service.nextValue() == 1)
            #expect(service.nextValue() == 2)
        }
        spy = nil
        #expect(weakTarget == nil)
    }

    @Test func getterHintsSupportThrowingGetterOverrideAndForwarding() throws {
        let forwardingState = SpyGetterAccessState()
        let forwardingSpy = try Spy<any SpyGetterService>(
            forwardingTo: RealSpyGetterService(state: forwardingState),
            getterEffects: .throwing,
            .nonthrowing,
            .throwing
        )
        let forwarded: any SpyGetterService = forwardingSpy()
        #expect(try forwarded.throwingValue == "forwarded")
        #expect(forwardingState.accesses == ["throwing"])

        let overridingState = SpyGetterAccessState()
        let overridingSpy = try Spy<any SpyGetterService>(
            forwardingTo: RealSpyGetterService(state: overridingState),
            getterEffects: .throwing,
            .nonthrowing,
            .throwing
        )
        overridingSpy.when { try $0.throwingValue }.thenReturn("overridden")
        let overridden: any SpyGetterService = overridingSpy()
        #expect(try overridden.throwingValue == "overridden")
        #expect(overridingState.accesses.isEmpty)
    }

    @Test func getterHintFactoryForwardsAndOverridesAsyncGetters() async throws {
        let state = SpyGetterAccessState()
        let spy: Spy<any SpyGetterService> = makeSpy(
            forwardingTo: RealSpyGetterService(state: state),
            getterEffects: .throwing,
            .nonthrowing,
            .throwing
        )
        await spy.when { await $0.asyncValue }.thenReturn(99)
        let service: any SpyGetterService = spy()

        #expect(await service.asyncValue == 99)
        #expect(try await service.asyncThrowingValue == "async-forwarded")
        #expect(state.accesses == ["async-throwing"])
    }
}
