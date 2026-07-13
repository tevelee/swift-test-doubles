import Testing
@testable import TestDoubles

private protocol RequirementProbe {
    func zero() -> Int
    func many(_ a: Int, _ b: String, _ c: Bool, _ d: Double, _ e: UInt, _ f: Float, _ g: Character) -> String
    var name: String { get }
}

typealias RequirementClosure = @Sendable (Int) -> Int

protocol ClosureRequirementProbe {
    func transform(_ closure: @escaping RequirementClosure) -> RequirementClosure
}

struct RealClosureRequirementProbe: ClosureRequirementProbe {
    func transform(_ closure: @escaping RequirementClosure) -> RequirementClosure { closure }
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

protocol LinkedRequirementProbe {
    func load(_ id: Int) async throws -> String
}

struct RealLinkedRequirementProbe: LinkedRequirementProbe {
    func load(_ id: Int) async throws -> String { "\(id)" }
}

enum EffectfulGetterProbeError: Error {
    case failed
}

protocol EffectfulGetterProbe {
    var value: Int { get async throws }
}

struct RealEffectfulGetterProbe: EffectfulGetterProbe {
    var value: Int {
        get async throws { 1 }
    }
}

enum TypedThrowsRequirementError: Error, Equatable {
    case failed
}

protocol TypedThrowsRequirementProbe {
    func load() throws(TypedThrowsRequirementError) -> Int
}

struct RealTypedThrowsRequirementProbe: TypedThrowsRequirementProbe {
    func load() throws(TypedThrowsRequirementError) -> Int { 1 }
}

enum SignatureMetatypeToken {}
typealias SignatureTuple = (id: Int, amount: Double)
typealias MixedSignatureTuple = (id: Int, Double, note: String)

protocol NormalizedSignatureProbe {
    func optional(_ value: String?) -> String?
    func tuple(_ value: SignatureTuple) -> SignatureTuple
    func mixedTuple(_ value: MixedSignatureTuple) -> MixedSignatureTuple
    func metatype(_ value: SignatureMetatypeToken.Type) -> SignatureMetatypeToken.Type
}

struct RealNormalizedSignatureProbe: NormalizedSignatureProbe {
    func optional(_ value: String?) -> String? { value }
    func tuple(_ value: SignatureTuple) -> SignatureTuple { value }
    func mixedTuple(_ value: MixedSignatureTuple) -> MixedSignatureTuple { value }
    func metatype(_ value: SignatureMetatypeToken.Type) -> SignatureMetatypeToken.Type { value }
}

private protocol SixIntegerAsyncRequirementProbe {
    func call(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int) async -> Int
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
            guard case .unsupportedProtocolShape(let protocolName, let reason) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "ClosureRequirementProbe")
            #expect(reason.contains("Requirement 0 contains a function"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func automaticallyDiscoveredClosureValuesUseTheSameShapeError() {
        _ = RealClosureRequirementProbe()
        expectUnsupportedProtocolShape {
            _ = try Stub<any ClosureRequirementProbe>()
        }
    }

    @Test func typedThrowsEffectsAreDiscovered() throws {
        _ = RealTypedThrowsRequirementProbe()
        let stub = try Stub<any TypedThrowsRequirementProbe>()
        #expect(stub.recorder.runtimeMethod(for: 0)?.isThrowing == true)
        stub.when { try $0.load() }.returns(42)
        #expect(try stub().load() == 42)
    }

    @Test func nestedParameterSyntaxResolvesConcreteMetadata() throws {
        _ = RealNormalizedSignatureProbe()
        let stub = try Stub<any NormalizedSignatureProbe>()
        let optional = try #require(stub.recorder.runtimeMethod(for: 0))
        let tuple = try #require(stub.recorder.runtimeMethod(for: 1))
        let mixedTuple = try #require(stub.recorder.runtimeMethod(for: 2))
        let metatype = try #require(stub.recorder.runtimeMethod(for: 3))

        #expect(ObjectIdentifier(optional.argumentTypes[0]) == ObjectIdentifier(String?.self))
        #expect(ObjectIdentifier(optional.returnType) == ObjectIdentifier(String?.self))
        #expect(ObjectIdentifier(tuple.argumentTypes[0]) == ObjectIdentifier(SignatureTuple.self))
        #expect(ObjectIdentifier(tuple.returnType) == ObjectIdentifier(SignatureTuple.self))
        #expect(
            ObjectIdentifier(mixedTuple.argumentTypes[0]) ==
                ObjectIdentifier(MixedSignatureTuple.self)
        )
        #expect(ObjectIdentifier(mixedTuple.returnType) == ObjectIdentifier(MixedSignatureTuple.self))
        #expect(
            ObjectIdentifier(metatype.argumentTypes[0]) ==
                ObjectIdentifier(SignatureMetatypeToken.Type.self)
        )
        #expect(ObjectIdentifier(metatype.returnType) == ObjectIdentifier(SignatureMetatypeToken.Type.self))
    }

    @Test func asyncGetterEffectsRequireExplicitConstruction() async throws {
        _ = RealEffectfulGetterProbe()
        do {
            _ = try Stub<any EffectfulGetterProbe>()
            Issue.record("Expected automatic effectful-getter discovery to be rejected")
        } catch let error as StubError {
            guard case .signatureDiscoveryFailed(let protocolName, let requirementIndex, _) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "EffectfulGetterProbe")
            #expect(requirementIndex == 0)
        }

        let stub = try Stub<any EffectfulGetterProbe>(
            .getter(Int.self, isThrowing: true, isAsync: true)
        )
        await stub.when { try await $0.value }.returns(7)
        #expect(try await stub().value == 7)

        do {
            _ = try Stub<any EffectfulGetterProbe>(
                .getter(String.self, isThrowing: true, isAsync: true)
            )
            Issue.record("Expected the getter return mismatch to be rejected")
        } catch let error as StubError {
            guard case .requirementMismatch(_, _, let expected, _) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(expected.contains("throwing effect unavailable"))
        }
    }

    @Test func explicitRequirementsAreValidatedAgainstLinkedConformances() {
        _ = RealLinkedRequirementProbe()
        do {
            _ = try Stub<any LinkedRequirementProbe>(
                .method(Int.self, returning: Int.self, isAsync: true)
            )
            Issue.record("Expected the explicit signature mismatch to be rejected")
        } catch let error as StubError {
            guard case .requirementMismatch(
                let protocolName, let requirementIndex, let expected, let actual
            ) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "LinkedRequirementProbe")
            #expect(requirementIndex == 0)
            #expect(expected.contains("async throws"))
            #expect(expected.contains("Swift.String"))
            #expect(actual.contains("async"))
            #expect(actual.contains("Swift.Int"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func x86AsyncRegisterBoundaryHasAConstructionGuard() throws {
        let method = MethodDescriptor(
            kind: .method,
            name: "call(_:_:_:_:_:_:)",
            index: 0,
            argumentTypes: [Int.self, Int.self, Int.self, Int.self, Int.self, Int.self],
            returnType: Int.self,
            isAsync: true
        )
        #expect(unsupportedRuntimeReason(for: method, architecture: .arm64) == nil)
        #expect(unsupportedRuntimeReason(for: method, architecture: .x86_64) != nil)

        #if arch(x86_64)
        expectUnsupportedProtocolShape {
            _ = try Stub<any SixIntegerAsyncRequirementProbe>(
                .method(
                    Int.self, Int.self, Int.self, Int.self, Int.self, Int.self,
                    returning: Int.self,
                    isAsync: true
                )
            )
        }
        #else
        _ = try Stub<any SixIntegerAsyncRequirementProbe>(
            .method(
                Int.self, Int.self, Int.self, Int.self, Int.self, Int.self,
                returning: Int.self,
                isAsync: true
            )
        )
        #endif
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
