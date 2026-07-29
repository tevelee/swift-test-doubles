import Testing
@testable import TestDoublesRuntimeSupport

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

    @Test func runtimeTypeResolutionAllowsRecursiveLookup() {
        let parent = "TestDoublesTests.RuntimeSymbolsTests.Parent"
        let child = "TestDoublesTests.RuntimeSymbolsTests.Child"

        let resolved = RuntimeSymbols.cachedRuntimeType(named: parent) {
            RuntimeSymbols.cachedRuntimeType(named: child) {
                Int.self
            }
        }

        #expect(resolved == Int.self)
    }

    @Test func processRuntimeSymbolAddressesAreStable() {
        let first = RuntimeSymbols.rawSymbol(named: "swift_conformsToProtocol")
        let second = RuntimeSymbols.rawSymbol(named: "swift_conformsToProtocol")

        #expect(first != nil)
        #expect(first == second)
    }

    @Test func successfulSymbolNameResolutionIsCached() {
        var marker = 0
        var attempts = 0

        withUnsafePointer(to: &marker) { pointer in
            let address = UnsafeRawPointer(pointer)
            let first = RuntimeSymbols.cachedSymbolName(at: address) {
                attempts += 1
                return "first"
            }
            let second = RuntimeSymbols.cachedSymbolName(at: address) {
                attempts += 1
                return "second"
            }

            #expect(first == "first")
            #expect(second == "first")
        }
        #expect(attempts == 1)
    }

    @Test func failedSymbolNameResolutionIsRetried() {
        var marker = 0
        var attempts = 0

        withUnsafePointer(to: &marker) { pointer in
            let address = UnsafeRawPointer(pointer)
            let missing = RuntimeSymbols.cachedSymbolName(
                at: address,
                exact: true
            ) {
                attempts += 1
                return nil
            }
            let resolved = RuntimeSymbols.cachedSymbolName(
                at: address,
                exact: true
            ) {
                attempts += 1
                return "resolved"
            }

            #expect(missing == nil)
            #expect(resolved == "resolved")
        }
        #expect(attempts == 2)
    }
}
import TestDoublesRuntime
