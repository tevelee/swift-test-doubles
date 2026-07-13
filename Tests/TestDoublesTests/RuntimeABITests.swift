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
#endif // RUNTIME_STUB
