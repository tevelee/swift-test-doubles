import Testing
import TestDoubles
import TestDoublesCxxInteropFixtures

/// End-to-end coverage for using TestDoubles from a `.interoperabilityMode(.Cxx)` target.
///
/// A protocol constrained to a C++ foreign reference superclass
/// (`Stub<any Widget & Greeter>()`) isn't supported: there's no generic way
/// to default-construct an arbitrary foreign reference instance or attach
/// fabricated resources' lifetime to one. That shape fails closed instead.
protocol Greeter {
    func greet() -> String
}

/// A foreign-reference payload must cross both directions of the fabricated
/// witness. This is deliberately unconstrained: only superclass-constrained
/// foreign reference existentials remain unsupported.
protocol WidgetTransporter {
    func replace(_ widget: Widget) -> Widget
}

private final class RealGreeter: Greeter {
    func greet() -> String { "hello" }
}

private final class RealWidgetTransporter: WidgetTransporter {
    func replace(_ widget: Widget) -> Widget { widget }
}

/// Kept reachable so automatic discovery finds a linked conformer instead of
/// failing earlier for lack of any conformance record.
private func useLinkedGreeter(_ value: any Greeter) -> String {
    value.greet()
}

@inline(never)
private func useLinkedWidgetTransporter(
    _ value: any WidgetTransporter,
    widget: Widget
) -> Widget {
    value.replace(widget)
}

@Suite struct CxxForeignReferenceTests {
    /// C++ interop and ordinary TestDoubles stubbing coexist in one target.
    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, visionOS 1.0, *)
    func cxxInteropAndOrdinaryStubbingCoexistInTheSameTarget() {
        let widget = Widget()
        #expect(widget.value() == 42)
        #expect(useLinkedGreeter(RealGreeter()) == "hello")

        let stub = try! Stub<any Greeter>()
        stub.when { $0.greet() }.thenReturn("hello, stub")

        let greeter: any Greeter = stub()
        #expect(greeter.greet() == "hello, stub")
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, visionOS 1.0, *)
    func fabricatedWitnessTransportsCxxForeignReferencesDirectly() throws {
        let request = Widget()
        request.setValue(17)
        let response = Widget()
        response.setValue(29)
        let captor = ArgumentCaptor<Widget>()
        #expect(
            useLinkedWidgetTransporter(
                RealWidgetTransporter(),
                widget: request
            ).value() == 17
        )

        let stub = try Stub<any WidgetTransporter>(
            .method(Widget.self, returning: Widget.self)
        )
        stub.when(returning: response) {
            $0.replace(captor.capture(using: request))
        }.thenReturn(response)

        let transporter: any WidgetTransporter = stub()
        let result = transporter.replace(request)

        #expect(captor.first?.value() == 17)
        #expect(result.value() == 29)
        stub.verify(returning: response) {
            $0.replace(any(using: request))
        }
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, visionOS 1.0, *)
    func foreignReferenceSuperclassConstraintFailsClosedWithTheActualBlocker() {
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
