import Testing
import TestDoubles

protocol VariadicEventLog {
    func record(_ events: String...) -> Int
}

struct LiveVariadicEventLog: VariadicEventLog {
    func record(_ events: String...) -> Int { events.count }
}

private struct VariadicEventLogStubConformer: VariadicEventLog, ManualStubConformer {
    let stub: CompiledStub<Self>

    func record(_ events: String...) -> Int { stub.call(events) }
}

/// `Match.anyVariadic()` stands for every remaining element of a variadic
/// argument, while other matchers still match one element each.
@Suite struct VariadicRequirementTests {
    @Test func anyVariadicMatchesAnyNumberOfElements() throws {
        let log = try Stub<any VariadicEventLog>(discoveringFrom: LiveVariadicEventLog())
        log.when { $0.record(Match.anyVariadic()) }.thenReturn(1)

        #expect(log().record() == 1)
        #expect(log().record("a") == 1)
        #expect(log().record("a", "b", "c") == 1)
        log.verify(3 ... 3) { $0.record(Match.anyVariadic()) }
    }

    @Test func anyVariadicFollowsFixedLeadingElements() throws {
        let log = try Stub<any VariadicEventLog>(discoveringFrom: LiveVariadicEventLog())
        log.when { $0.record(Match.equal("started"), Match.anyVariadic()) }.thenReturn(1)
        log.when { $0.record(Match.anyVariadic()) }.thenReturn(0)

        #expect(log().record("started") == 1)
        #expect(log().record("started", "user:7") == 1)
        #expect(log().record("stopped", "user:7") == 0)
        #expect(log().record() == 0)
    }

    @Test func singleMatchersStillMatchExactlyOneElement() throws {
        let log = try Stub<any VariadicEventLog>(discoveringFrom: LiveVariadicEventLog())
        log.when { $0.record(Match.any()) }.thenReturn(1)
        log.when { $0.record(Match.anyVariadic()) }.thenReturn(99)

        #expect(log().record("a") == 1)
        #expect(log().record("a", "b") == 99)
    }

    @Test func compiledConformersAcceptAnyVariadic() {
        let log = CompiledStub<VariadicEventLogStubConformer>()
        log.when { $0.record(Match.anyVariadic()) }.thenReturn(5)

        #expect(log().record("a", "b") == 5)
    }
}
