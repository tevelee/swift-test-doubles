import Testing
@testable import TestDoubles

private protocol RequirementProbe {
    func zero() -> Int
    func many(_ a: Int, _ b: String, _ c: Bool, _ d: Double, _ e: UInt, _ f: Float, _ g: Character) -> String
    var name: String { get }
}

private typealias RequirementClosure = @Sendable (Int) -> Int

private protocol ClosureRequirementProbe {
    func transform(_ closure: @escaping RequirementClosure) -> RequirementClosure
}

private protocol ClassConstrainedRequirementProbe: AnyObject {
    func call()
}

private final class RealClassConstrainedRequirementProbe: ClassConstrainedRequirementProbe {
    func call() {}
}

private protocol BaseRequirementProbe {
    func base()
}

private protocol InheritedRequirementProbe: BaseRequirementProbe {
    func child()
}

private struct RealInheritedRequirementProbe: InheritedRequirementProbe {
    func base() {}
    func child() {}
}

private protocol AssociatedRequirementProbe {
    associatedtype Value
    func value() -> Value
}

private protocol InitializerRequirementProbe {
    init()
}

private protocol StaticRequirementProbe {
    static func make()
}

@Suite struct RequirementTests {
    @Test func explicitRequirementsSupportZeroAndHighArityMethods() throws {
        let stub = try Stub<any RequirementProbe>(
            .method(returning: Int.self),
            .method(
                Int.self, String.self, Bool.self, Double.self, UInt.self, Float.self, Character.self,
                returning: String.self
            ),
            .getter(String.self)
        )
        stub.when { $0.zero() }.returns(7)
        stub.when { $0.many(any(), any(), any(), any(), any(), any(), any()) }.then {
            (a: Int, b: String, c: Bool, d: Double, e: UInt, f: Float, g: Character) in
            "\(a):\(b):\(c):\(d):\(e):\(f):\(g)"
        }
        stub.when { $0.name }.returns("before")

        let probe: any RequirementProbe = stub()
        #expect(probe.zero() == 7)
        #expect(probe.many(1, "two", true, 4, 5, 6, "7") == "1:two:true:4.0:5:6.0:7")
        #expect(probe.name == "before")
    }

    @Test func closureValuesAreRejectedBeforeInvocation() {
        do {
            _ = try Stub<any ClosureRequirementProbe>(
                .method(RequirementClosure.self, returning: RequirementClosure.self)
            )
            Issue.record("Expected function values to be rejected")
        } catch let error as StubError {
            guard case .unsupportedFunctionValue(let protocolName, let requirement) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "ClosureRequirementProbe")
            #expect(requirement == 0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func unsupportedProtocolLayoutsAndStructuralRequirementsAreRejected() {
        expectUnsupportedProtocolShape {
            _ = try Stub<any ClassConstrainedRequirementProbe>()
        }
        expectUnsupportedProtocolShape {
            _ = try Stub<any ClassConstrainedRequirementProbe>(
                .method(returning: Void.self)
            )
        }
        expectUnsupportedProtocolShape {
            _ = try Stub<any InheritedRequirementProbe>()
        }
        expectUnsupportedProtocolShape {
            _ = try Stub<any AssociatedRequirementProbe>(
                .method(returning: Int.self)
            )
        }
        expectUnsupportedProtocolShape {
            _ = try Stub<any InitializerRequirementProbe>()
        }
        expectUnsupportedProtocolShape {
            _ = try Stub<any StaticRequirementProbe>()
        }
    }
}

private func expectUnsupportedProtocolShape(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected an unsupported-protocol-shape error")
    } catch let error as StubError {
        guard case .unsupportedProtocolShape = error else {
            Issue.record("Unexpected StubError: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
