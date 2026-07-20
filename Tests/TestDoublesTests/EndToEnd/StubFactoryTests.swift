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

protocol FactoryAsyncService {
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
        let service: any FactoryCurrencyService = makeStub {
            $0.when { $0.currency }.then { "EUR" }
        }

        #expect(service.currency == "EUR")
    }

    @Test func configuresAsyncRequirements() async {
        let service: any FactoryAsyncService = await makeStub {
            await $0.when { await $0.load() }.then { "loaded" }
        }

        #expect(await service.load() == "loaded")
    }

    @Test func sendableProtocolsRequireAnExplicitUncheckedBoundary() {
        _ = LiveFactorySendableService()
        let service: any FactorySendableService = makeStub {
            $0.when { $0.value }.thenReturn(42)
        }

        #expect(service.value == 42)
    }

    @Test func asyncFactoryPreservesTheExplicitUncheckedBoundary() async {
        _ = LiveFactorySendableService()
        let service: any FactorySendableService = await makeStub {
            stub in
            await Task.yield()
            stub.when { $0.value }.thenReturn(42)
        }

        #expect(service.value == 42)
    }
}
