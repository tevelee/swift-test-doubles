#if RUNTIME_STUB
import Testing
@testable import TestDoubles

struct LargeABIResult: Equatable, Sendable {
    let id: Int
    let amount: Double
    let label: String
    let accepted: Bool
}

struct DirectAggregateABIResult: Equatable, Sendable {
    let label: String
    let amount: Double
    let accepted: Bool
}

struct MixedAggregateABIArgument: Equatable, Sendable {
    let amount: Double
    let accepted: Bool
}

struct SmallABIPair: Equatable, Sendable {
    let left: Int32
    let right: Int32
}

final class ABIReferenceBox {
    let value: Int

    init(value: Int) {
        self.value = value
    }
}

struct ABIThrownError: Error, Equatable {
    let code: Int
}

enum PayloadABIEnum: Equatable, Sendable {
    case idle
    case code(Int)
}

typealias MixedABITuple = (id: Int, amount: Double)
typealias ABIClosure = @Sendable (Int) -> Int

enum ABIMetatypeToken: Sendable {}

protocol ABIExistentialValue: Sendable {
    var id: Int { get }
}

struct FirstABIExistentialValue: ABIExistentialValue {
    let id: Int
}

struct SecondABIExistentialValue: ABIExistentialValue {
    let id: Int
}

private enum RuntimeABITaskValues {
    @TaskLocal static var marker: String?
}

protocol FloatingABIProbe {
    func mix(_ a: Float, _ b: Double, _ c: Float) -> Double
}

struct RealFloatingABIProbe: FloatingABIProbe {
    func mix(_ a: Float, _ b: Double, _ c: Float) -> Double {
        Double(a) + b + Double(c)
    }
}

protocol FloatingStackABIProbe {
    func sum(
        _ f0: Float, _ f1: Float, _ f2: Float, _ f3: Float, _ f4: Float,
        _ f5: Float, _ f6: Float, _ f7: Float, _ f8: Float, _ d9: Double
    ) -> Double
}

protocol StackArgumentABIProbe {
    func sum(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
        _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
    ) -> Int
}

struct RealStackArgumentABIProbe: StackArgumentABIProbe {
    func sum(
        _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
        _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int, _ a9: Int
    ) -> Int {
        [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9].reduce(0, +)
    }
}

protocol CustomArgumentABIProbe {
    func describe(pair: SmallABIPair, box: ABIReferenceBox) -> String
}

struct RealCustomArgumentABIProbe: CustomArgumentABIProbe {
    func describe(pair: SmallABIPair, box: ABIReferenceBox) -> String {
        "\(pair.left):\(pair.right):\(box.value)"
    }
}

protocol MixedAggregateArgumentABIProbe {
    func describe(id: Int, payload: MixedAggregateABIArgument, scale: Double) -> String
}

struct RealMixedAggregateArgumentABIProbe: MixedAggregateArgumentABIProbe {
    func describe(id: Int, payload: MixedAggregateABIArgument, scale: Double) -> String {
        "\(id):\(payload.amount):\(payload.accepted):\(scale)"
    }
}

protocol ThrowingABIProbe {
    func load(code: Int) throws -> String
}

struct RealThrowingABIProbe: ThrowingABIProbe {
    func load(code: Int) throws -> String {
        "\(code)"
    }
}

protocol DirectAggregateReturnABIProbe {
    func load(id: Int) -> DirectAggregateABIResult
}

struct RealDirectAggregateReturnABIProbe: DirectAggregateReturnABIProbe {
    func load(id: Int) -> DirectAggregateABIResult {
        DirectAggregateABIResult(label: "\(id)", amount: 0, accepted: false)
    }
}

protocol IndirectReturnABIProbe {
    func load(id: Int) -> LargeABIResult
}

struct RealIndirectReturnABIProbe: IndirectReturnABIProbe {
    func load(id: Int) -> LargeABIResult {
        LargeABIResult(id: id, amount: 0, label: "", accepted: false)
    }
}

protocol ExplicitSlotMetadataABIProbe {
    func load(id: Int, payload: MixedAggregateABIArgument) throws -> LargeABIResult
}

protocol AsyncRuntimeABIProbe: Sendable {
    func noArguments() async -> Int
    func integer(_ value: Int) async -> Int
    func floating(_ value: Double) async -> Double
    func direct(_ id: Int) async -> DirectAggregateABIResult
    func indirect(_ id: Int) async -> LargeABIResult
    func finish() async
}

struct RealAsyncRuntimeABIProbe: AsyncRuntimeABIProbe {
    func noArguments() async -> Int { 0 }
    func integer(_ value: Int) async -> Int { value }
    func floating(_ value: Double) async -> Double { value }
    func direct(_ id: Int) async -> DirectAggregateABIResult {
        DirectAggregateABIResult(label: "\(id)", amount: 0, accepted: false)
    }
    func indirect(_ id: Int) async -> LargeABIResult {
        LargeABIResult(id: id, amount: 0, label: "", accepted: false)
    }
    func finish() async {}
}

protocol ExtendedAsyncRuntimeABIProbe: Sendable {
    func enumValue(_ value: PayloadABIEnum) async -> PayloadABIEnum
    func optional(_ value: String?) async -> String?
    func tuple(_ value: MixedABITuple) async -> MixedABITuple
    func metatype(_ value: ABIMetatypeToken.Type) async -> ABIMetatypeToken.Type
    func existential(_ value: any ABIExistentialValue) async -> any ABIExistentialValue
}

protocol AsyncClosureABIProbe: Sendable {
    func closure(_ value: @escaping ABIClosure) async -> ABIClosure
}

@Suite struct RuntimeABITests {
    @Test func mixedFloatAndDoubleArguments() {
        let stub = RuntimeStub<any FloatingABIProbe>()
        stub.when { $0.mix(any(), any(), any()) }.then { args in
            let a = args[0] as! Float
            let b = args[1] as! Double
            let c = args[2] as! Float
            return Double(a) + b + Double(c)
        }

        let sut: any FloatingABIProbe = stub()

        #expect(sut.mix(1.5, 2.25, 3.75) == 7.5)
    }

    @Test func floatingPointArgumentsSpillOntoStack() throws {
        let slot = Slot.method(
            args: Array(repeating: Float.self, count: 9) + [Double.self],
            returns: Double.self
        )
        let stub = try RuntimeStub<any FloatingStackABIProbe>.make(slot)

        stub.when {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }.then { args in
            let floats = try args.prefix(9).map { value -> Float in
                try #require(value as? Float)
            }
            let double = try #require(args[9] as? Double)
            #expect(floats == [1, 2, 3, 4, 5, 6, 7, 8, 9])
            #expect(double == 10.5)
            return Double(floats.reduce(0, +)) + double
        }

        let sut: any FloatingStackABIProbe = stub()

        #expect(sut.sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10.5) == 55.5)
    }

    @Test func integerArgumentsSpillOntoStack() {
        let stub = RuntimeStub<any StackArgumentABIProbe>()
        stub.when {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }.then { args in
            let values = args.map { $0 as! Int }
            #expect(values == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            return values.reduce(0, +)
        }

        let sut: any StackArgumentABIProbe = stub()

        #expect(sut.sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) == 55)
    }

    @Test func typedHandlersSupportArityBeyondPreviousLimit() {
        let stub = RuntimeStub<any StackArgumentABIProbe>()
        stub.when {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }.then {
            (a0: Int, a1: Int, a2: Int, a3: Int, a4: Int,
             a5: Int, a6: Int, a7: Int, a8: Int, a9: Int) in
            [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9].reduce(0, +)
        }

        let sut: any StackArgumentABIProbe = stub()
        let result = sut.sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
        var captured: [Int] = []

        stub.verify {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }.withArgs {
            (a0: Int, a1: Int, a2: Int, a3: Int, a4: Int,
             a5: Int, a6: Int, a7: Int, a8: Int, a9: Int) in
            captured = [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9]
        }

        #expect(result == 55)
        #expect(captured == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    }

    @Test func customValueAndReferenceArgumentsDecode() throws {
        let stub = RuntimeStub<any CustomArgumentABIProbe>()
        let slot = try methodSlot(containing: "describe", in: stub)
        let box = ABIReferenceBox(value: 42)

        stub.recorder.addStub(method: slot, matchers: [], returnValue: { args in
            let pair = args[0] as! SmallABIPair
            let decodedBox = args[1] as! ABIReferenceBox
            #expect(pair == SmallABIPair(left: 7, right: 11))
            #expect(decodedBox === box)
            return "\(pair.left):\(pair.right):\(decodedBox.value)"
        })

        let sut: any CustomArgumentABIProbe = stub()

        #expect(sut.describe(pair: SmallABIPair(left: 7, right: 11), box: box) == "7:11:42")
    }

    @Test func mixedAggregateArgumentDecodesFromIntegerAndFloatingPointRegisters() {
        let stub = RuntimeStub<any MixedAggregateArgumentABIProbe>()
        let expected = MixedAggregateABIArgument(amount: 13.5, accepted: true)

        stub.when { $0.describe(id: any(), payload: any(), scale: any()) }.then { args in
            #expect(args[0] as? Int == 42)
            #expect(args[1] as? MixedAggregateABIArgument == expected)
            #expect(args[2] as? Double == 2.0)
            return "decoded"
        }

        let sut: any MixedAggregateArgumentABIProbe = stub()

        #expect(sut.describe(id: 42, payload: expected, scale: 2.0) == "decoded")
    }

    @Test func throwingFailurePropagatesThroughSwiftErrorRegister() {
        let stub = RuntimeStub<any ThrowingABIProbe>()
        stub.when { try $0.load(code: any()) }.then { args in
            throw ABIThrownError(code: args[0] as! Int)
        }

        let sut: any ThrowingABIProbe = stub()
        let error = #expect(throws: ABIThrownError.self) {
            try sut.load(code: 404)
        }
        #expect(error?.code == 404)
    }

    @Test func directAggregateReturnIsEncodedIntoMixedRegisters() {
        let stub = RuntimeStub<any DirectAggregateReturnABIProbe>()
        let expected = DirectAggregateABIResult(label: "direct", amount: 12.5, accepted: true)

        stub.when { $0.load(id: any()) }.returns(expected)

        let sut: any DirectAggregateReturnABIProbe = stub()

        #expect(sut.load(id: 7) == expected)
    }

    @Test func indirectReturnIsEncodedIntoCallerBuffer() throws {
        let stub = RuntimeStub<any IndirectReturnABIProbe>()
        let expected = LargeABIResult(id: 7, amount: 19.5, label: "sret", accepted: true)

        stub.when { $0.load(id: any()) }.returns(expected)

        let sut: any IndirectReturnABIProbe = stub()

        #expect(sut.load(id: 7) == expected)
    }

    @Test func explicitSlotMetadataSupportsThrowingIndirectReturnWithoutConformer() throws {
        let payload = MixedAggregateABIArgument(amount: 21.5, accepted: true)
        let expected = LargeABIResult(id: 9, amount: 21.5, label: "explicit", accepted: true)
        let stub = try RuntimeStub<any ExplicitSlotMetadataABIProbe>.make(
            .method(
                args: [Int.self, MixedAggregateABIArgument.self],
                returns: LargeABIResult.self,
                throws: true
            )
        )

        stub.when { try $0.load(id: any(), payload: any()) }.then { args in
            #expect(args[0] as? Int == 9)
            #expect(args[1] as? MixedAggregateABIArgument == payload)
            return expected
        }

        let sut: any ExplicitSlotMetadataABIProbe = stub()

        #expect(try sut.load(id: 9, payload: payload) == expected)
    }

    @Test func asyncReturnsUseContinuationABI() async throws {
        let stub = RuntimeStub<any AsyncRuntimeABIProbe>()
        let direct = DirectAggregateABIResult(label: "async-direct", amount: 12.5, accepted: true)
        let indirect = LargeABIResult(id: 7, amount: 19.5, label: "async-indirect", accepted: true)

        await stub.when { await $0.noArguments() }.returns(9)
        await stub.when { await $0.integer(equal(1)) } then: { args in
            (args[0] as! Int) + 41
        }
        await stub.when { await $0.integer(equal(2)) } then: { 44 }
        await stub.when { await $0.floating(any()) }.returns(6.25)
        await stub.when { await $0.direct(any()) }.returns(direct)
        await stub.when { await $0.indirect(any()) }.returns(indirect)
        await stub.when { await $0.finish() }

        let sut: any AsyncRuntimeABIProbe = stub()

        #expect(await sut.noArguments() == 9)
        #expect(await sut.integer(1) == 42)
        #expect(await sut.integer(2) == 44)
        #expect(await sut.floating(2) == 6.25)
        #expect(await sut.direct(3) == direct)
        #expect(await sut.indirect(4) == indirect)
        await sut.finish()
    }

    @Test func suspendingAsyncHandlersReturnAcrossABIs() async throws {
        let stub = RuntimeStub<any AsyncRuntimeABIProbe>()
        let direct = DirectAggregateABIResult(label: "suspended-direct", amount: 3.5, accepted: true)
        let indirect = LargeABIResult(id: 11, amount: 8.25, label: "suspended-indirect", accepted: true)

        await stub.when({ await $0.noArguments() }, thenAsync: {
            await Task.yield()
            return 17
        })
        await stub.when({ await $0.integer(any()) }, thenAsync: { args in
            await Task.yield()
            return (args[0] as! Int) + 1
        })
        await stub.when({ await $0.floating(any()) }, thenAsync: {
            await Task.yield()
            return 6.75
        })
        await stub.when({ await $0.direct(any()) }, thenAsync: {
            await Task.yield()
            return direct
        })
        await stub.when({ await $0.indirect(any()) }, thenAsync: {
            await Task.yield()
            return indirect
        })
        await stub.when({ await $0.finish() }, thenAsync: {
            await Task.yield()
        })

        let sut: any AsyncRuntimeABIProbe = stub()

        #expect(await sut.noArguments() == 17)
        #expect(await sut.integer(41) == 42)
        #expect(await sut.floating(2) == 6.75)
        #expect(await sut.direct(3) == direct)
        #expect(await sut.indirect(4) == indirect)
        await sut.finish()
    }

    @Test func immediateAsyncHandlersSupportExtendedABIShapes() async throws {
        let stub = try makeExtendedAsyncABIStub()

        await stub.when({ await $0.enumValue(equal(.code(7))) }, then: { args in
            let value = args[0] as! PayloadABIEnum
            #expect(value == .code(7))
            return PayloadABIEnum.code(8)
        })
        await stub.when({ await $0.optional(equal(Optional("optional"))) }, then: { args in
            let value = args[0] as! String?
            #expect(value == "optional")
            return value?.uppercased()
        })
        await stub.when({ await $0.tuple((id: 9, amount: 2.5)) }, then: { args in
            let value = args[0] as! MixedABITuple
            #expect(value.id == 9)
            #expect(value.amount == 2.5)
            return (id: value.id + 1, amount: value.amount + 0.5)
        })
        await stub.when({ await $0.metatype(ABIMetatypeToken.self) }, then: { args in
            let type = args[0] as! ABIMetatypeToken.Type
            #expect(type == ABIMetatypeToken.self)
            return type
        })
        await stub.when({
            await $0.existential(FirstABIExistentialValue(id: 12))
        }, then: { args in
            let value = args[0] as! any ABIExistentialValue
            return SecondABIExistentialValue(id: value.id + 1)
        })

        let sut: any ExtendedAsyncRuntimeABIProbe = stub()
        let tuple = await sut.tuple((id: 9, amount: 2.5))
        let existential = await sut.existential(FirstABIExistentialValue(id: 12))

        #expect(await sut.enumValue(.code(7)) == .code(8))
        #expect(await sut.optional("optional") == "OPTIONAL")
        #expect(tuple.id == 10)
        #expect(tuple.amount == 3)
        #expect(await sut.metatype(ABIMetatypeToken.self) == ABIMetatypeToken.self)
        #expect(existential.id == 13)
        #expect(existential is SecondABIExistentialValue)

        await stub.verify { await $0.enumValue(equal(.code(7))) }.wasCalled()
        await stub.verify { await $0.optional(equal(Optional("optional"))) }.wasCalled()
        await stub.verify { await $0.tuple((id: 9, amount: 2.5)) }.wasCalled()
        await stub.verify { await $0.metatype(ABIMetatypeToken.self) }.wasCalled()
        await stub.verify {
            await $0.existential(FirstABIExistentialValue(id: 12))
        }.wasCalled()
    }

    @Test func suspendingAsyncHandlersSupportExtendedABIShapes() async throws {
        let stub = try makeExtendedAsyncABIStub()

        await stub.when({ await $0.enumValue(equal(.code(17))) }, thenAsync: { args in
            await Task.yield()
            let value = try #require(args[0] as? PayloadABIEnum)
            #expect(value == .code(17))
            return PayloadABIEnum.code(18)
        })
        await stub.when({
            await $0.optional(equal(Optional("suspended")))
        }, thenAsync: { args in
            await Task.yield()
            let value = try #require(args[0] as? String?)
            #expect(value == "suspended")
            return value?.uppercased()
        })
        await stub.when({
            await $0.tuple((id: 19, amount: 4.5))
        }, thenAsync: { args in
            await Task.yield()
            let value = try #require(args[0] as? MixedABITuple)
            #expect(value.id == 19)
            #expect(value.amount == 4.5)
            return (id: value.id + 1, amount: value.amount + 0.5)
        })
        await stub.when({
            await $0.metatype(ABIMetatypeToken.self)
        }, thenAsync: { args in
            await Task.yield()
            let type = try #require(args[0] as? ABIMetatypeToken.Type)
            #expect(type == ABIMetatypeToken.self)
            return type
        })
        await stub.when({
            await $0.existential(FirstABIExistentialValue(id: 22))
        }, thenAsync: { args in
            await Task.yield()
            let value = try #require(args[0] as? any ABIExistentialValue)
            return SecondABIExistentialValue(id: value.id + 1)
        })

        let sut: any ExtendedAsyncRuntimeABIProbe = stub()
        let tuple = await sut.tuple((id: 19, amount: 4.5))
        let existential = await sut.existential(FirstABIExistentialValue(id: 22))

        #expect(await sut.enumValue(.code(17)) == .code(18))
        #expect(await sut.optional("suspended") == "SUSPENDED")
        #expect(tuple.id == 20)
        #expect(tuple.amount == 5)
        #expect(await sut.metatype(ABIMetatypeToken.self) == ABIMetatypeToken.self)
        #expect(existential.id == 23)
        #expect(existential is SecondABIExistentialValue)
    }

    @Test func closureRequirementsFailBeforeInvocation() {
        do {
            _ = try RuntimeStub<any AsyncClosureABIProbe>.make(
                .method(ABIClosure.self, returns: ABIClosure.self, async: true)
            )
            Issue.record("Expected closure requirement to be rejected")
        } catch let error as RuntimeStubError {
            guard case .unsupportedFunctionValue(let protocolName, let methodName) = error else {
                Issue.record("Unexpected RuntimeStubError: \(error)")
                return
            }
            #expect(protocolName == "AsyncClosureABIProbe")
            #expect(methodName == "slot_0")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func suspendingHandlerPreservesTaskLocalValues() async {
        let stub = RuntimeStub<any AsyncRuntimeABIProbe>()

        await stub.when({ await $0.integer(any()) }, thenAsync: { args in
            #expect(RuntimeABITaskValues.marker == "caller")
            await Task.yield()
            #expect(RuntimeABITaskValues.marker == "caller")
            return args[0] as! Int
        })

        let sut: any AsyncRuntimeABIProbe = stub()
        let result = await RuntimeABITaskValues.$marker.withValue("caller") {
            await sut.integer(29)
        }

        #expect(result == 29)
    }

    @MainActor
    @Test func suspendingHandlerPreservesActorIsolation() async {
        let stub = RuntimeStub<any AsyncRuntimeABIProbe>()

        await stub.when({ await $0.noArguments() }, thenAsync: {
            MainActor.preconditionIsolated()
            await Task.yield()
            MainActor.preconditionIsolated()
            return 31
        })
        await stub.when { await $0.integer(any()) }.returns(33)

        let sut: any AsyncRuntimeABIProbe = stub()
        #expect(await sut.noArguments() == 31)
        #expect(await sut.integer(0) == 33)
        await stub.verify { await $0.noArguments() }.wasCalled()
    }

    @Test func concurrentAsyncCallsAreRecordedSafely() async {
        let stub = RuntimeStub<any AsyncRuntimeABIProbe>()
        await stub.when({ await $0.integer(any()) }, thenAsync: { args in
            await Task.yield()
            return args[0] as! Int
        })

        let total = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for value in 0..<100 {
                group.addTask {
                    let sut: any AsyncRuntimeABIProbe = stub()
                    return await sut.integer(value)
                }
            }
            return await group.reduce(0, +)
        }

        #expect(total == (0..<100).reduce(0, +))
        #expect(stub.calls.filter { $0.name.contains("integer") }.count == 100)
    }
}

private func methodSlot<P>(
    containing needle: String,
    in stub: RuntimeStub<P>,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> Int {
    let match = try #require(
        stub.recorder.runtimeMethods.first { $0.value.name.contains(needle) },
        "Expected runtime method containing \(needle)",
        sourceLocation: sourceLocation
    )
    return match.key
}

private func makeExtendedAsyncABIStub() throws -> RuntimeStub<any ExtendedAsyncRuntimeABIProbe> {
    try RuntimeStub<any ExtendedAsyncRuntimeABIProbe>.make(
        .method(PayloadABIEnum.self, returns: PayloadABIEnum.self, async: true),
        .method(Optional<String>.self, returns: Optional<String>.self, async: true),
        .method(MixedABITuple.self, returns: MixedABITuple.self, async: true),
        .method(ABIMetatypeToken.Type.self, returns: ABIMetatypeToken.Type.self, async: true),
        .method(
            (any ABIExistentialValue).self,
            returns: (any ABIExistentialValue).self,
            async: true
        )
    )
}

#endif // RUNTIME_STUB
