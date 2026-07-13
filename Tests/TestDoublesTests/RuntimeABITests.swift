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
    init(value: Int) { self.value = value }
}

struct ABIThrownError: Error, Equatable {
    let code: Int
}

enum PayloadABIEnum: Equatable, Sendable {
    case idle
    case code(Int)
}

typealias MixedABITuple = (id: Int, amount: Double)

enum ABIMetatypeToken: Sendable {}

protocol ABIExistentialValue: Sendable {
    var id: Int { get }
}

struct FirstABIExistentialValue: ABIExistentialValue { let id: Int }
struct SecondABIExistentialValue: ABIExistentialValue { let id: Int }

private enum StubTaskValues {
    @TaskLocal static var marker: String?
}

protocol FloatingABIProbe {
    func mix(_ a: Float, _ b: Double, _ c: Float) -> Double
}

struct RealFloatingABIProbe: FloatingABIProbe {
    func mix(_ a: Float, _ b: Double, _ c: Float) -> Double { Double(a) + b + Double(c) }
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
    ) -> Int { [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9].reduce(0, +) }
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
    func describe(id: Int, payload: MixedAggregateABIArgument, scale: Double) -> String { "" }
}

protocol ThrowingABIProbe {
    func load(code: Int) throws -> String
}

struct RealThrowingABIProbe: ThrowingABIProbe {
    func load(code: Int) throws -> String { "\(code)" }
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

protocol ExplicitMetadataABIProbe {
    func load(id: Int, payload: MixedAggregateABIArgument) throws -> LargeABIResult
}

protocol AsyncABIProbe: Sendable {
    func noArguments() async -> Int
    func integer(_ value: Int) async -> Int
    func floating(_ value: Double) async -> Double
    func direct(_ id: Int) async -> DirectAggregateABIResult
    func indirect(_ id: Int) async -> LargeABIResult
    func finish() async
}

struct RealAsyncABIProbe: AsyncABIProbe {
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

protocol ExtendedAsyncABIProbe: Sendable {
    func enumValue(_ value: PayloadABIEnum) async -> PayloadABIEnum
    func optional(_ value: String?) async -> String?
    func tuple(_ value: MixedABITuple) async -> MixedABITuple
    func metatype(_ value: ABIMetatypeToken.Type) async -> ABIMetatypeToken.Type
    func existential(_ value: any ABIExistentialValue) async -> any ABIExistentialValue
}

@Suite struct RuntimeABITests {
    @Test func mixedFloatingPointArguments() throws {
        let stub = try Stub<any FloatingABIProbe>()
        stub.when { $0.mix(any(), any(), any()) }.then {
            (a: Float, b: Double, c: Float) in Double(a) + b + Double(c)
        }

        #expect(stub().mix(1.5, 2.25, 3.75) == 7.5)
    }

    @Test func floatingPointArgumentsSpillOntoStack() throws {
        let stub = try Stub<any FloatingStackABIProbe>(
            .method(
                Float.self, Float.self, Float.self, Float.self, Float.self,
                Float.self, Float.self, Float.self, Float.self, Double.self,
                returning: Double.self
            )
        )
        stub.when {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }.then {
            (f0: Float, f1: Float, f2: Float, f3: Float, f4: Float,
             f5: Float, f6: Float, f7: Float, f8: Float, d9: Double) in
            Double(f0 + f1 + f2 + f3 + f4 + f5 + f6 + f7 + f8) + d9
        }

        #expect(stub().sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10.5) == 55.5)
    }

    @Test func integerArgumentsAndTypedHandlersExceedOldArityLimit() throws {
        let stub = try Stub<any StackArgumentABIProbe>()
        stub.when {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }.then {
            (a0: Int, a1: Int, a2: Int, a3: Int, a4: Int,
             a5: Int, a6: Int, a7: Int, a8: Int, a9: Int) in
            [a0, a1, a2, a3, a4, a5, a6, a7, a8, a9].reduce(0, +)
        }

        #expect(stub().sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) == 55)
        stub.verify {
            $0.sum(any(), any(), any(), any(), any(), any(), any(), any(), any(), any())
        }
    }

    @Test func customValueAndReferenceArgumentsDecode() throws {
        let stub = try Stub<any CustomArgumentABIProbe>()
        let box = ABIReferenceBox(value: 42)
        stub.when { $0.describe(pair: any(), box: any()) }.then {
            (pair: SmallABIPair, decodedBox: ABIReferenceBox) in
            #expect(pair == SmallABIPair(left: 7, right: 11))
            #expect(decodedBox === box)
            return "\(pair.left):\(pair.right):\(decodedBox.value)"
        }

        #expect(stub().describe(pair: SmallABIPair(left: 7, right: 11), box: box) == "7:11:42")
    }

    @Test func mixedAggregateArgumentUsesIntegerAndFloatingPointRegisters() throws {
        let stub = try Stub<any MixedAggregateArgumentABIProbe>()
        let payload = MixedAggregateABIArgument(amount: 13.5, accepted: true)
        stub.when { $0.describe(id: any(), payload: any(), scale: any()) }.then {
            (id: Int, decoded: MixedAggregateABIArgument, scale: Double) in
            #expect(id == 42)
            #expect(decoded == payload)
            #expect(scale == 2)
            return "decoded"
        }

        #expect(stub().describe(id: 42, payload: payload, scale: 2) == "decoded")
    }

    @Test func throwingFailureUsesSwiftErrorRegister() throws {
        let stub = try Stub<any ThrowingABIProbe>()
        stub.when { try $0.load(code: any()) }.then { (code: Int) throws in
            throw ABIThrownError(code: code)
        }

        let error = #expect(throws: ABIThrownError.self) { try stub().load(code: 404) }
        #expect(error?.code == 404)
    }

    @Test func directAndIndirectAggregateReturns() throws {
        let directStub = try Stub<any DirectAggregateReturnABIProbe>()
        let indirectStub = try Stub<any IndirectReturnABIProbe>()
        let direct = DirectAggregateABIResult(label: "direct", amount: 12.5, accepted: true)
        let indirect = LargeABIResult(id: 7, amount: 19.5, label: "sret", accepted: true)
        directStub.when { $0.load(id: any()) }.returns(direct)
        indirectStub.when { $0.load(id: any()) }.returns(indirect)

        #expect(directStub().load(id: 1) == direct)
        #expect(indirectStub().load(id: 2) == indirect)
    }

    @Test func explicitMetadataSupportsThrowingIndirectReturn() throws {
        let stub = try Stub<any ExplicitMetadataABIProbe>(
            .method(
                Int.self, MixedAggregateABIArgument.self,
                returning: LargeABIResult.self,
                isThrowing: true
            )
        )
        let payload = MixedAggregateABIArgument(amount: 21.5, accepted: true)
        let expected = LargeABIResult(id: 9, amount: 21.5, label: "explicit", accepted: true)
        stub.when { try $0.load(id: any(), payload: any()) }.then {
            (id: Int, value: MixedAggregateABIArgument) throws in
            #expect(id == 9)
            #expect(value == payload)
            return expected
        }

        #expect(try stub().load(id: 9, payload: payload) == expected)
    }

    @Test func asyncContinuationsReturnAcrossABIShapes() async throws {
        let stub = try Stub<any AsyncABIProbe>()
        let direct = DirectAggregateABIResult(label: "async", amount: 3.5, accepted: true)
        let indirect = LargeABIResult(id: 11, amount: 8.25, label: "async", accepted: true)
        await stub.when { await $0.noArguments() }.then {
            () async throws -> Int in
            await Task.yield()
            return 17
        }
        await stub.when { await $0.integer(any()) }.then {
            (value: Int) async throws -> Int in
            await Task.yield()
            return value + 1
        }
        await stub.when { await $0.floating(any()) }.returns(6.75)
        await stub.when { await $0.direct(any()) }.returns(direct)
        await stub.when { await $0.indirect(any()) }.returns(indirect)
        await stub.when { await $0.finish() }.then {
            () async throws -> Void in await Task.yield()
        }

        let probe: any AsyncABIProbe = stub()
        #expect(await probe.noArguments() == 17)
        #expect(await probe.integer(41) == 42)
        #expect(await probe.floating(2) == 6.75)
        #expect(await probe.direct(3) == direct)
        #expect(await probe.indirect(4) == indirect)
        await probe.finish()

        await stub.verify { await $0.finish() }
    }

    @Test func asyncEnumValueShape() async throws {
        let stub = try makeExtendedAsyncStub()
        await stub.when { await $0.enumValue(any()) }.then {
            (value: PayloadABIEnum) async throws -> PayloadABIEnum in
            guard case .code(let code) = value else { return .idle }
            return .code(code + 1)
        }

        #expect(await stub().enumValue(.code(7)) == .code(8))
    }

    @Test func asyncOptionalValueShape() async throws {
        let stub = try makeExtendedAsyncStub()
        await stub.when { await $0.optional(any()) }.then {
            (value: String?) async throws -> String? in value?.uppercased()
        }

        #expect(await stub().optional("optional") == "OPTIONAL")
    }

    @Test func asyncTupleValueShape() async throws {
        let stub = try makeExtendedAsyncStub()
        await stub.when { await $0.tuple(any()) }.then {
            (value: MixedABITuple) async throws -> MixedABITuple in
            (id: value.id + 1, amount: value.amount + 0.5)
        }

        let tuple = await stub().tuple((id: 9, amount: 2.5))
        #expect(tuple.id == 10)
        #expect(tuple.amount == 3)
    }

    @Test func asyncMetatypeValueShape() async throws {
        let stub = try makeExtendedAsyncStub()
        await stub.when { await $0.metatype(any()) }.then {
            (type: ABIMetatypeToken.Type) async throws -> ABIMetatypeToken.Type in type
        }

        #expect(await stub().metatype(ABIMetatypeToken.self) == ABIMetatypeToken.self)
    }

    @Test func asyncExistentialValueShape() async throws {
        let stub = try makeExtendedAsyncStub()
        await stub.when { await $0.existential(FirstABIExistentialValue(id: 12)) }
            .returns(SecondABIExistentialValue(id: 13))

        let existential = await stub().existential(FirstABIExistentialValue(id: 12))
        #expect(existential.id == 13)
        #expect(existential is SecondABIExistentialValue)
    }

    @Test func asyncHandlerPreservesTaskContext() async throws {
        let stub = try Stub<any AsyncABIProbe>()
        let expectedPriority = Task.currentPriority
        await stub.when { await $0.integer(any()) }.then {
            (value: Int) async throws -> Int in
            #expect(StubTaskValues.marker == "caller")
            #expect(Task.currentPriority == expectedPriority)
            await Task.yield()
            #expect(StubTaskValues.marker == "caller")
            #expect(Task.currentPriority == expectedPriority)
            return value
        }

        let result = await StubTaskValues.$marker.withValue("caller") {
            await stub().integer(42)
        }
        #expect(result == 42)
    }

    @MainActor
    @Test func asyncHandlerPreservesActorIsolation() async throws {
        let stub = try Stub<any AsyncABIProbe>()
        await stub.when { await $0.integer(any()) }.then {
            (value: Int) async throws -> Int in
            MainActor.assertIsolated()
            await Task.yield()
            MainActor.assertIsolated()
            return value
        }

        #expect(await stub().integer(42) == 42)
    }
}

private func makeExtendedAsyncStub() throws -> Stub<any ExtendedAsyncABIProbe> {
    try Stub<any ExtendedAsyncABIProbe>(
        .method(PayloadABIEnum.self, returning: PayloadABIEnum.self, isAsync: true),
        .method(String?.self, returning: String?.self, isAsync: true),
        .method(MixedABITuple.self, returning: MixedABITuple.self, isAsync: true),
        .method(ABIMetatypeToken.Type.self, returning: ABIMetatypeToken.Type.self, isAsync: true),
        .method(
            (any ABIExistentialValue).self,
            returning: (any ABIExistentialValue).self,
            isAsync: true
        )
    )
}
