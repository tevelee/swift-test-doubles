import Testing
@testable import TestDoubles

@Suite struct RuntimeSymbolsTests {
    @Test func successfulRuntimeTypeResolutionIsCached() {
        var attempts = 0
        let name = "TestDoublesTests.RuntimeSymbolsTests.Cached"

        let first = RuntimeSymbols.cachedRuntimeType(named: name) {
            attempts += 1
            return Int.self
        }
        let second = RuntimeSymbols.cachedRuntimeType(named: name) {
            attempts += 1
            return String.self
        }

        #expect(first == Int.self)
        #expect(second == Int.self)
        #expect(attempts == 1)
    }

    @Test func failedRuntimeTypeResolutionIsRetried() {
        var attempts = 0
        let name = "TestDoublesTests.RuntimeSymbolsTests.Retry"

        let missing = RuntimeSymbols.cachedRuntimeType(named: name) {
            attempts += 1
            return nil
        }
        let resolved = RuntimeSymbols.cachedRuntimeType(named: name) {
            attempts += 1
            return String.self
        }

        #expect(missing == nil)
        #expect(resolved == String.self)
        #expect(attempts == 2)
    }

    @Test func processRuntimeSymbolAddressesAreStable() {
        let first = RuntimeSymbols.rawSymbol(named: "swift_conformsToProtocol")
        let second = RuntimeSymbols.rawSymbol(named: "swift_conformsToProtocol")

        #expect(first != nil)
        #expect(first == second)
    }
}
