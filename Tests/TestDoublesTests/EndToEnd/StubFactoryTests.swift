import Testing
import TestDoubles

// Internal, not private: automatic-discovery fixtures must keep their
// conformance records reachable in release builds.
protocol FactoryCurrencyService {
    var currency: String { get }
}

struct LiveFactoryCurrencyService: FactoryCurrencyService {
    var currency: String { "USD" }
}

protocol FactoryAsyncService: Sendable {
    func load() async -> String
}

struct LiveFactoryAsyncService: FactoryAsyncService {
    func load() async -> String { "live" }
}

protocol FactorySendableService: Sendable {
    var value: Int { get }
}

struct LiveFactorySendableService: FactorySendableService {
    var value: Int { 0 }
}

@Suite("Stub factory")
struct StubFactoryTests {
    @Test func returnsAConfiguredProtocolValue() {
        let service: any FactoryCurrencyService = Stub.make {
            $0.when { $0.currency }.then { "EUR" }
        }

        #expect(service.currency == "EUR")
    }

    @Test func cachedPreparationStillCreatesIndependentRecorders() throws {
        _ = LiveFactoryCurrencyService()
        let first = try Stub<any FactoryCurrencyService>()
        let second = try Stub<any FactoryCurrencyService>()
        first.when { $0.currency }.thenReturn("EUR")
        second.when { $0.currency }.thenReturn("HUF")

        #expect(first().currency == "EUR")
        #expect(second().currency == "HUF")
    }

    @Test func cachedExplicitPreparationStillCreatesIndependentRecorders() throws {
        _ = LiveFactoryCurrencyService()
        let requirement: Stub<any FactoryCurrencyService>.Requirement =
            .getter(String.self)
        let first = try Stub<any FactoryCurrencyService>(requirement)
        let second = try Stub<any FactoryCurrencyService>(requirement)
        first.when { $0.currency }.thenReturn("EUR")
        second.when { $0.currency }.thenReturn("HUF")

        #expect(first().currency == "EUR")
        #expect(second().currency == "HUF")
    }

    @Test func prewarmingAutomaticPreparationCreatesNoSharedRecorderState() throws {
        _ = LiveFactoryCurrencyService()
        try Stub<any FactoryCurrencyService>.prewarm()
        try Stub<any FactoryCurrencyService>.prewarm()

        let first = try Stub<any FactoryCurrencyService>()
        let second = try Stub<any FactoryCurrencyService>()
        first.when { $0.currency }.thenReturn("EUR")
        second.when { $0.currency }.thenReturn("HUF")

        #expect(first().currency == "EUR")
        #expect(second().currency == "HUF")
    }

    @Test func prewarmingReportsTheSameTypedConstructionError() {
        #expect(throws: StubError.self) {
            try Stub<Int>.prewarm()
        }
    }

    @Test func reportsConstructionAndDispatchPerformance() throws {
        _ = LiveFactoryCurrencyService()
        let stub = try Stub<any FactoryCurrencyService>()
        let empty = stub.performanceDiagnostics

        #expect(
            empty.construction.totalDuration
                == empty.construction.planPreparationDuration
                + empty.construction.materializationDuration
        )
        #expect(empty.dispatch.callCount == 0)
        #expect(empty.dispatch.averageDuration == nil)

        stub.when { $0.currency }.thenReturn("EUR")
        #expect(stub().currency == "EUR")
        #expect(stub().currency == "EUR")

        let diagnostics = stub.performanceDiagnostics
        #expect(diagnostics.dispatch.callCount == 2)
        #expect(diagnostics.dispatch.completedCallCount == 2)
        #expect(diagnostics.dispatch.pendingCallCount == 0)
        #expect(diagnostics.dispatch.averageDuration != nil)
        #expect(diagnostics.dispatch.maximumDuration != nil)
        #expect(diagnostics.dispatch.methods.count == 1)
        #expect(diagnostics.dispatch.methods[0].method.contains("currency"))
        #expect(diagnostics.dispatch.methods[0].callCount == 2)
        #expect(diagnostics.description.contains("Construction:"))
        #expect(diagnostics.description.contains("Dispatch: 2 calls"))
    }

    @Test func performanceDiagnosticsIncludePendingAsyncDispatch() async throws {
        let stub = try Stub<any FactoryAsyncService>()
        let suspension = await stub.when { await $0.load() }.thenSuspend()
        let service: any FactoryAsyncService = stub()
        let task = Task { await service.load() }
        await suspension.waitForCall()

        let pending = stub.performanceDiagnostics.dispatch
        #expect(pending.callCount == 1)
        #expect(pending.completedCallCount == 0)
        #expect(pending.pendingCallCount == 1)
        #expect(pending.averageDuration == nil)
        #expect(pending.methods[0].pendingCallCount == 1)

        suspension.resume(returning: "loaded")
        #expect(await task.value == "loaded")

        let completed = stub.performanceDiagnostics.dispatch
        #expect(completed.completedCallCount == 1)
        #expect(completed.pendingCallCount == 0)
        #expect(completed.averageDuration != nil)
    }

    @Test func configuresAsyncRequirements() async {
        let service: any FactoryAsyncService = await Stub.make {
            await $0.when { await $0.load() }.then { "loaded" }
        }

        #expect(await service.load() == "loaded")
    }

    @Test func sendableProtocolsRequireAnExplicitUncheckedBoundary() {
        _ = LiveFactorySendableService()
        let service: any FactorySendableService = Stub.make {
            $0.when { $0.value }.thenReturn(42)
        }

        #expect(service.value == 42)
    }

    @Test func asyncFactoryPreservesTheExplicitUncheckedBoundary() async {
        _ = LiveFactorySendableService()
        let service: any FactorySendableService = await Stub.make {
            stub in
            await Task.yield()
            stub.when { $0.value }.thenReturn(42)
        }

        #expect(service.value == 42)
    }
}
