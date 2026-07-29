import Testing
@testable import TestDoubles

private enum InjectedFault: Error, Equatable {
    case transient
}

private protocol FaultInjectionService {
    func load(_ value: Int) throws -> Int
}

private struct RealFaultInjectionService: FaultInjectionService {
    func load(_ value: Int) throws -> Int { value }
}

@Suite struct FaultInjectionBehaviorTests {
    @Test func everyNthCallFailsInInvocationOrder() throws {
        _ = RealFaultInjectionService()
        let stub = try Stub<any FaultInjectionService>()
        let pattern = stub.when { try $0.load(Match.any()) }
        pattern.thenInjectFailure(
            every: 3,
            throwing: InjectedFault.transient,
            otherwiseReturning: 42
        )
        let service: any FaultInjectionService = stub()

        let outcomes = (1 ... 7).map { _ in
            Result { try service.load(0) }
        }

        #expect(
            outcomes.map(\.isSuccess)
                == [true, true, false, true, true, false, true]
        )
        #expect(pattern.results() == [42, 42, 42, 42, 42])
        #expect(pattern.errors(ofType: InjectedFault.self) == [.transient, .transient])
    }

    @Test func equalSeedsProduceEqualProbabilitySequences() throws {
        _ = RealFaultInjectionService()
        let first = try outcomeSequence(seed: 0xC0FFEE)
        let second = try outcomeSequence(seed: 0xC0FFEE)
        let different = try outcomeSequence(seed: 0xBAD5EED)

        #expect(first == second)
        #expect(first != different)
        #expect(first.contains(true))
        #expect(first.contains(false))
    }

    @Test func throwingClosurePatternSharesSeededFaultInjection() throws {
        let closure = ThrowingClosureDouble<Int, Int>()
        closure.whenAny().thenInjectFailure(
            every: 2,
            throwing: InjectedFault.transient,
            otherwiseReturning: 7
        )

        #expect(try closure(1) == 7)
        #expect(throws: InjectedFault.transient) {
            try closure(2)
        }
        #expect(try closure(3) == 7)
    }

    private func outcomeSequence(seed: UInt64) throws -> [Bool] {
        let stub = try Stub<any FaultInjectionService>()
        stub.when { try $0.load(Match.any()) }.thenInjectFailure(
            probability: 0.35,
            seed: seed,
            throwing: InjectedFault.transient,
            otherwiseReturning: 1
        )
        let service: any FaultInjectionService = stub()
        return (0 ..< 64).map { _ in
            (try? service.load(0)) != nil
        }
    }
}

extension Result {
    fileprivate var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}
