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

    @Test func nonsendingSymbolsDemangleOnOlderProcessRuntimes() {
        let mangled =
            "$s19TestDoublesFixtures34RealExternalExtendedClosureServiceVAA0efgH0A2aDP10nonsendingySSSiYaYbYCcSSSiYaYbYCcFTW"
        let closure =
            "nonisolated(nonsending) @Sendable (Swift.Int) async -> Swift.String"
        let expected =
            "protocol witness for TestDoublesFixtures.ExternalExtendedClosureService.nonsending("
            + closure
            + ") -> "
            + closure
            + " in conformance TestDoublesFixtures.RealExternalExtendedClosureService : TestDoublesFixtures.ExternalExtendedClosureService in TestDoublesFixtures"

        #expect(RuntimeSymbols.demangle(mangled) == expected)
    }

    @Test func nonsendingCompatibilityPreservesIsolatedAnyAttributes() {
        let mangled =
            "$s19TestDoublesFixtures34RealExternalExtendedClosureServiceVAA0efgH0A2aDP8isolatedySSSiYaYbYAcSSSiYaYbYCcFTW"
        let expected =
            "protocol witness for TestDoublesFixtures.ExternalExtendedClosureService.isolated("
            + "nonisolated(nonsending) @Sendable (Swift.Int) async -> Swift.String"
            + ") -> @isolated(any) @Sendable (Swift.Int) async -> Swift.String"
            + " in conformance TestDoublesFixtures.RealExternalExtendedClosureService : TestDoublesFixtures.ExternalExtendedClosureService in TestDoublesFixtures"

        #expect(RuntimeSymbols.demangle(mangled) == expected)
    }

    @Test func implicitActorThunkSymbolsDemangleOnOlderProcessRuntimes() {
        let mangled =
            "$sBASiSSIeghHgILnr_BASiSSIeghHgILyo_TR"
        let direct =
            "@escaping @callee_guaranteed @Sendable @async"
            + " (@guaranteed Builtin.ImplicitActor, @in_guaranteed Swift.Int)"
            + " -> (@out Swift.String)"
        let generic =
            "@escaping @callee_guaranteed @Sendable @async"
            + " (@guaranteed Builtin.ImplicitActor, @unowned Swift.Int)"
            + " -> (@owned Swift.String)"
        let expected =
            "reabstraction thunk helper from \(direct) to \(generic)"

        #expect(RuntimeSymbols.demangle(mangled) == expected)
    }

    @Test func isolatedParameterThunkSymbolsDemangleOnOlderProcessRuntimes() {
        let mangled =
            "$s19TestDoublesFixtures21ExternalClosureWorkerCS2iIeghHgIyd_ACS2iIeghHnInr_TR"
        let direct =
            "@escaping @callee_guaranteed @Sendable @async"
            + " (@guaranteed isolated TestDoublesFixtures.ExternalClosureWorker,"
            + " @unowned Swift.Int) -> (@unowned Swift.Int)"
        let generic =
            "@escaping @callee_guaranteed @Sendable @async"
            + " (@in_guaranteed isolated TestDoublesFixtures.ExternalClosureWorker,"
            + " @in_guaranteed Swift.Int) -> (@out Swift.Int)"
        let expected =
            "reabstraction thunk helper from \(direct) to \(generic)"

        #expect(RuntimeSymbols.demangle(mangled) == expected)
    }

    @Test func coroutinePointerSymbolsDemangleOnOlderProcessRuntimes() {
        let mangled =
            "$s23TestDoublesReadFixtures018ForwardingConcreteC13AccessorProbeCAA0fcgH0A2aDP7integerSivyTWTwc"
        let expected =
            "coro function pointer to protocol witness for"
            + " TestDoublesReadFixtures.ConcreteReadAccessorProbe.integer.read2"
            + " : Swift.Int in conformance"
            + " TestDoublesReadFixtures.ForwardingConcreteReadAccessorProbe"
            + " : TestDoublesReadFixtures.ConcreteReadAccessorProbe"
            + " in TestDoublesReadFixtures"

        #expect(RuntimeSymbols.demangle(mangled) == expected)
    }
}
import TestDoublesRuntime
