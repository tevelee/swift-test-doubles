import Testing
@testable import TestDoublesRuntimeMetadata

@Suite struct ReabstractionThunkRegistryTests {
    /// This exact shape has no reabstraction thunk in the test binary. A
    /// lookup therefore refreshes the registry after reading its snapshot.
    private typealias UnlinkedFunction =
        @Sendable (
            UInt8,
            Int16,
            Float,
            String,
            (Int, String)
        ) async throws -> (UInt64, Int)

    // Captured with `nm ... | swift-demangle` from this package's own
    // compiled test binary: a real generic reabstraction thunk helper, where
    // NodePrinter.cpp inserts the thunk's own generic clause ("<A> ")
    // between "helper " and "from ".
    private static let genericHelperSpelling =
        "partial apply forwarder for reabstraction thunk helper <A> from "
        + "@callee_guaranteed (@unowned Swift.Int) -> (@unowned Swift.Bool) "
        + "to @escaping @callee_guaranteed (@in_guaranteed Swift.Int) "
        + "-> (@out Swift.Bool)"

    private static let plainHelperSpelling =
        "partial apply forwarder for reabstraction thunk helper from "
        + "@callee_guaranteed (@unowned Swift.Int) -> (@unowned Swift.Bool) "
        + "to @escaping @callee_guaranteed (@in_guaranteed Swift.Int) "
        + "-> (@out Swift.Bool)"

    @Test func parsesAThunkThatCarriesItsOwnGenericSignature() throws {
        let pair = try #require(reabstractionPair(in: Self.genericHelperSpelling))
        #expect(pair.sourceIsGeneric == false)
        #expect(pair.source.canonicalSpelling.contains("@unowned Swift.Int"))
        #expect(pair.target.canonicalSpelling.contains("@in_guaranteed Swift.Int"))
    }

    @Test func parsesAThunkWithNoGenericSignature() throws {
        let pair = try #require(reabstractionPair(in: Self.plainHelperSpelling))
        #expect(pair.sourceIsGeneric == false)
    }

    @Test func bodyAfterHelperRejectsAMalformedGenericClause() {
        #expect(bodyAfterHelper(in: "<A something from x to y"[...]) == nil)
    }

    /// Regression test for an index-space bug: `bodyAfterHelper` used to
    /// build a scanner from a freshly copied `String(demangled)` but then
    /// index into it with `demangled`'s own (pre-copy) indices, which are
    /// only valid when the substring's storage starts at offset 0. Slicing
    /// off a wrapper prefix first (as `reabstractionPair` always does)
    /// reproduces the mismatch that a bare string literal cannot.
    @Test func bodyAfterHelperWorksOnASubstringSlicedFromALargerString() {
        let full = "prefix <A> from x to y"
        let sliced = full[full.index(full.startIndex, offsetBy: 7)...]
        #expect(bodyAfterHelper(in: sliced).map(String.init) == "x to y")
    }

    @Test func concurrentUnlinkedLookupsRefreshSafely() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    #expect(
                        ReabstractionThunkRegistry.shared.directToGeneric(
                            for: UnlinkedFunction.self
                        ) == nil
                    )
                }
            }
        }
    }
}
import TestDoublesRuntime
