import Testing
import TestDoublesFixtures
@testable import TestDoubles

// Internal, not private: automatic-discovery fixtures must keep their
// conformance records reachable in release builds.
protocol ConstrainedGenericArgumentProbe {
    func unwrap(_ box: ExternalConstrainedAssociatedBox<Int>) -> Int
    func combine(_ pair: ExternalBothParametersConstrainedPair<Int, Int>) -> Int
    func multiplyConstrained(_ box: ExternalMultiplyConstrainedBox<Int>) -> Int
    func severalConstrained(
        _ value: ExternalSeveralConstrainedArguments<String, Bool, Int>
    ) -> Int
}

struct RealConstrainedGenericArgumentProbe: ConstrainedGenericArgumentProbe {
    func unwrap(_ box: ExternalConstrainedAssociatedBox<Int>) -> Int { box.value }
    func combine(_ pair: ExternalBothParametersConstrainedPair<Int, Int>) -> Int {
        pair.first + pair.second
    }
    func multiplyConstrained(_ box: ExternalMultiplyConstrainedBox<Int>) -> Int {
        box.value
    }
    func severalConstrained(
        _ value: ExternalSeveralConstrainedArguments<String, Bool, Int>
    ) -> Int {
        value.value
    }
}

@Suite struct ConstrainedGenericTypeResolutionTests {
    @Test func automaticDiscoveryResolvesConstrainedGenericArguments() throws {
        // Regression test: automatic discovery used to fail closed here --
        // ExternalConstrainedAssociatedBox<Value: Hashable> needs one
        // witness-table key argument and
        // ExternalBothParametersConstrainedPair<First: Hashable,
        // Second: Hashable> needs two, both beyond what genericNominalType
        // could supply before, so signature discovery failed before
        // construction ever reached ABI-classification concerns.
        let stub = try Stub<any ConstrainedGenericArgumentProbe>()
        stub.when(returning: 0) {
            $0.unwrap(any(using: ExternalConstrainedAssociatedBox(0)))
        }.then { (box: ExternalConstrainedAssociatedBox<Int>) in
            box.value * 2
        }
        stub.when(returning: 0) {
            $0.combine(
                any(using: ExternalBothParametersConstrainedPair(0, 0))
            )
        }.then { (pair: ExternalBothParametersConstrainedPair<Int, Int>) in
            pair.first + pair.second
        }
        stub.when(returning: 0) {
            $0.multiplyConstrained(
                any(using: ExternalMultiplyConstrainedBox(0))
            )
        }.then { (box: ExternalMultiplyConstrainedBox<Int>) in
            box.value * 2
        }
        stub.when(returning: 0) {
            $0.severalConstrained(
                any(
                    using: ExternalSeveralConstrainedArguments<
                        String,
                        Bool,
                        Int
                    >(
                        0
                    )
                )
            )
        }.then {
            (
                value: ExternalSeveralConstrainedArguments<
                    String,
                    Bool,
                    Int
                >
            ) in
            value.value * 2
        }

        let probe = stub()
        #expect(probe.unwrap(ExternalConstrainedAssociatedBox(21)) == 42)
        #expect(probe.combine(ExternalBothParametersConstrainedPair(3, 4)) == 7)
        #expect(probe.multiplyConstrained(ExternalMultiplyConstrainedBox(21)) == 42)
        #expect(
            probe.severalConstrained(
                ExternalSeveralConstrainedArguments<String, Bool, Int>(21)
            ) == 42
        )
    }
}
