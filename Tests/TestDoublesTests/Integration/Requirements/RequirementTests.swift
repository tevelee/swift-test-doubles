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

enum ClosureRequirementError: Error, Equatable {
    case failed
}

protocol TypedThrowingClosureRequirementProbe {
    func transform(
        _ closure: @escaping RequirementClosure
    ) throws(ClosureRequirementError) -> RequirementClosure
}

protocol ClosureAndValueRequirementProbe {
    func apply(_ closure: @escaping RequirementClosure, to value: Int) -> Int
}

typealias ManagedClosure = (String) -> String

protocol ManagedClosureRequirementProbe {
    func transform(_ closure: @escaping ManagedClosure) -> ManagedClosure
}

struct RealManagedClosureRequirementProbe: ManagedClosureRequirementProbe {
    func transform(_ closure: @escaping ManagedClosure) -> ManagedClosure { closure }
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

protocol LinkedRequirementProbe {
    func load(_ id: Int) async throws -> String
}

struct RealLinkedRequirementProbe: LinkedRequirementProbe {
    func load(_ id: Int) async throws -> String { "\(id)" }
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

protocol SelfResultRequirementProbe {
    func duplicate() -> Self
}

struct RealSelfResultRequirementProbe: SelfResultRequirementProbe {
    func duplicate() -> Self { self }
}

protocol SelfArgumentRequirementProbe {
    func combine(_ other: Self) -> Self
}

struct RealSelfArgumentRequirementProbe: SelfArgumentRequirementProbe {
    let marker: Int

    func combine(_ other: Self) -> Self { other }
}

@inline(never)
private func useLinkedSelfResult(
    _ value: any SelfResultRequirementProbe
) -> any SelfResultRequirementProbe {
    value.duplicate()
}

@inline(never)
private func useLinkedSelfArgument<T: SelfArgumentRequirementProbe>(
    _ value: T
) -> T {
    value.combine(value)
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
        stub.when { $0.zero() }.thenReturn(7)
        stub.when { $0.many(any(), any(), any(), any(), any(), any(), any()) }.then {
            (a: Int, b: String, c: Bool, d: Double, e: UInt, f: Float, g: Character) in
            "\(a):\(b):\(c):\(d):\(e):\(f):\(g)"
        }
        stub.when { $0.name }.thenReturn("before")

        let probe: any RequirementProbe = stub()
        #expect(probe.zero() == 7)
        #expect(probe.many(1, "two", true, 4, 5, 6, "7") == "1:two:true:4.0:5:6.0:7")
        #expect(probe.name == "before")
    }

    @Test func typedAdapterTransportsClosureArgumentsAndResults() throws {
        let identity: RequirementClosure = { $0 }
        let adapter:
            @convention(thin) (
                @escaping RequirementClosure,
                Stub<any ClosureRequirementProbe>.Invocation
            ) -> RequirementClosure = { closure, invocation in
                invocation.call(closure)
            }
        let stub = try Stub<any ClosureRequirementProbe>(
            .method(
                RequirementClosure.self,
                returning: RequirementClosure.self,
                using: adapter
            )
        )
        stub.when(returning: identity) {
            $0.transform(any(using: identity))
        }.then { (closure: RequirementClosure) in
            let transformed = closure(20) + 2
            return { _ in transformed }
        }

        let probe: any ClosureRequirementProbe = stub()
        let supplied: RequirementClosure = { $0 * 2 }
        let result = probe.transform(supplied)

        #expect(result(0) == 42)
        let captor = ArgumentCaptor<RequirementClosure>()
        stub.verify(returning: identity) {
            $0.transform(captor.capture(using: identity))
        }
        #expect(captor.last?(3) == 6)
    }

    @Test func closureValuesWithoutATypedAdapterFailClosed() {
        expectStubError({
            _ = try Stub<any ClosureRequirementProbe>(
                .method(RequirementClosure.self, returning: RequirementClosure.self)
            )
        }) { error in
            guard case .unsupportedProtocolShape(let protocolName, let reason) = error else {
                return false
            }
            return protocolName == "ClosureRequirementProbe"
                && reason.contains("compiler-typed `using:` adapter")
        }
    }

    @Test func thickClosureCannotMasqueradeAsWitnessAdapter() {
        let adapter:
            (
                @escaping RequirementClosure,
                Stub<any ClosureRequirementProbe>.Invocation
            ) -> RequirementClosure = { closure, _ in closure }
        expectUnsupportedProtocolShape(containing: "`@convention(thin)`") {
            _ = try Stub<any ClosureRequirementProbe>(
                .method(
                    RequirementClosure.self,
                    returning: RequirementClosure.self,
                    using: adapter
                )
            )
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func typedAdapterPreservesTypedThrowsWithClosureValues() throws {
        let identity: RequirementClosure = { $0 }
        let adapter:
            @convention(thin) (
                @escaping RequirementClosure,
                Stub<any TypedThrowingClosureRequirementProbe>.Invocation
            ) throws(ClosureRequirementError) -> RequirementClosure = { closure, invocation in
                try invocation.call(
                    closure,
                    returning: RequirementClosure.self,
                    throwing: ClosureRequirementError.self
                )
            }
        let stub = try Stub<any TypedThrowingClosureRequirementProbe>(
            .method(
                RequirementClosure.self,
                returning: RequirementClosure.self,
                throwing: ClosureRequirementError.self,
                using: adapter
            )
        )
        stub.when(returning: identity) {
            try $0.transform(any(using: identity))
        }.thenThrow(ClosureRequirementError.failed)

        let probe: any TypedThrowingClosureRequirementProbe = stub()
        #expect(throws: ClosureRequirementError.failed) {
            try probe.transform(identity)
        }
    }

    @Test func escapingHandlerSupportsCallbackFollowedByOrdinaryArguments() throws {
        let identity: RequirementClosure = { $0 }
        let adapter:
            @convention(thin) (
                @escaping RequirementClosure,
                Int,
                Stub<any ClosureAndValueRequirementProbe>.Invocation
            ) -> Int = { closure, value, invocation in
                invocation.call(closure, value)
            }
        let stub = try Stub<any ClosureAndValueRequirementProbe>(
            .method(
                RequirementClosure.self,
                Int.self,
                returning: Int.self,
                using: adapter
            )
        )
        stub.when {
            $0.apply(any(using: identity), to: any())
        }.thenEscaping { (closure: RequirementClosure, value: Int) in
            closure(value) + 2
        }

        #expect(stub().apply({ $0 * 2 }, to: 20) == 42)
    }

    @Test func automaticallyDiscoveredClosureValuesDispatchWithoutRequirements() throws {
        _ = RealClosureRequirementProbe()
        let identity: RequirementClosure = { $0 }
        let stub = try Stub<any ClosureRequirementProbe>()
        stub.when(returning: identity) {
            $0.transform(any(using: identity))
        }.then { (closure: RequirementClosure) in
            let transformed = closure(20) + 2
            return { _ in transformed }
        }

        let probe: any ClosureRequirementProbe = stub()
        let result = probe.transform { $0 * 2 }
        let value = result(0)
        #expect(value == 42)
    }

    @Test func automaticManagedClosureValuesPreserveCapturedStorage() throws {
        _ = RealManagedClosureRequirementProbe()
        let identity: ManagedClosure = { $0 }
        let stub = try Stub<any ManagedClosureRequirementProbe>()
        stub.when(returning: identity) {
            $0.transform(any(using: identity))
        }.then { (closure: ManagedClosure) in
            let captured = closure("forty-")
            return { captured + $0 }
        }

        let result = stub().transform { $0 }
        #expect(result("two") == "forty-two")
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
            ObjectIdentifier(mixedTuple.argumentTypes[0]) == ObjectIdentifier(MixedSignatureTuple.self)
        )
        #expect(ObjectIdentifier(mixedTuple.returnType) == ObjectIdentifier(MixedSignatureTuple.self))
        #expect(
            ObjectIdentifier(metatype.argumentTypes[0]) == ObjectIdentifier(SignatureMetatypeToken.Type.self)
        )
        #expect(ObjectIdentifier(metatype.returnType) == ObjectIdentifier(SignatureMetatypeToken.Type.self))
    }

    @Test func explicitRequirementsAreValidatedAgainstLinkedConformances() {
        _ = RealLinkedRequirementProbe()
        expectStubError({
            _ = try Stub<any LinkedRequirementProbe>(
                .method(Int.self, returning: Int.self, isAsync: true)
            )
        }) { error in
            guard
                case .requirementMismatch(
                    let protocolName, let requirementIndex, let expected, let actual
                ) = error
            else {
                return false
            }
            return protocolName == "LinkedRequirementProbe"
                && requirementIndex == 0
                && expected.contains("async throws")
                && expected.contains("Swift.String")
                && actual.contains("async")
                && actual.contains("Swift.Int")
        }
    }

    @Test func asyncRegisterBoundariesHaveConstructionGuards() throws {
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

        let armBoundary = MethodDescriptor(
            kind: .method,
            name: "call(_:_:_:_:_:_:_:_:)",
            index: 0,
            argumentTypes: Array(repeating: Int.self, count: 8),
            returnType: Int.self,
            isAsync: true
        )
        #expect(unsupportedRuntimeReason(for: armBoundary, architecture: .arm64) != nil)

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

    @Test func unsupportedStructuralRequirementsAreRejected() {
        expectUnsupportedProtocolShape {
            _ = try Stub<any AssociatedRequirementProbe>(
                .method(returning: Int.self)
            )
        }
    }

    @Test func directSelfArgumentsAreRejected() {
        #expect(
            useLinkedSelfResult(RealSelfResultRequirementProbe())
                is RealSelfResultRequirementProbe
        )
        #expect(
            useLinkedSelfArgument(
                RealSelfArgumentRequirementProbe(marker: 42)
            ).marker == 42
        )
        expectUnsupportedProtocolShape {
            _ = try Stub<any SelfArgumentRequirementProbe>()
        }
    }
}
