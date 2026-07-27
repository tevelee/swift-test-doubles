import Testing
import TestDoubles
import TestDoublesCxxInteropFixtures

/// End-to-end coverage for building and using TestDoubles from a target with
/// `.interoperabilityMode(.Cxx)` enabled. See
/// CXX_FOREIGN_REFERENCE_FEASIBILITY.md for background: Echo 0.1.17 fixed the
/// `CEcho` build blocker that made this target impossible to build at all.
///
/// Full support for a protocol constrained to a C++ foreign reference
/// superclass (`Stub<any Widget & Greeter>()`, matching the existing
/// NSObject superclass-constrained existential-composition convention) is
/// not implemented: automatic Stub construction has no generic way to
/// default-construct an arbitrary foreign reference instance, or to attach
/// the fabricated runtime resources' lifetime to one (no
/// associated-object-equivalent mechanism exists for a non-Objective-C
/// reference type). Both gaps are unverified new design questions surfaced
/// while attempting this item, not yet resolved. That shape fails closed
/// with a diagnostic naming the actual blocker.
protocol Greeter {
    func greet() -> String
}

private final class RealGreeter: Greeter {
    func greet() -> String { "hello" }
}

/// Kept reachable so automatic discovery finds a linked conformer instead of
/// failing earlier for lack of any conformance record.
private func useLinkedGreeter(_ value: any Greeter) -> String {
    value.greet()
}

@Suite struct CxxForeignReferenceTests {
    /// The previously-impossible scenario: a target with C++ interop enabled
    /// that also depends on TestDoubles now builds and runs both halves.
    @Test func cxxInteropAndOrdinaryStubbingCoexistInTheSameTarget() {
        let widget = Widget()
        #expect(widget.value() == 42)
        #expect(useLinkedGreeter(RealGreeter()) == "hello")

        let stub = try! Stub<any Greeter>()
        stub.when { $0.greet() }.thenReturn("hello, stub")

        let greeter: any Greeter = stub()
        #expect(greeter.greet() == "hello, stub")
    }

    @Test func foreignReferenceSuperclassConstraintFailsClosedWithTheActualBlocker() {
        do {
            _ = try Stub<any Widget & Greeter>()
            Issue.record("Expected construction to fail closed")
        } catch {
            guard case .unsupportedProtocolShape(_, let reason) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(reason.contains("C++ foreign reference superclass"))
        }
    }
}
