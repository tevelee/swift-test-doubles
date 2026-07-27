import Testing
@testable import TestDoubles

final class InlineArrayLifetimeToken: Sendable {
    let id: Int

    init(id: Int) {
        self.id = id
    }
}

@available(
    macOS 26.0,
    iOS 26.0,
    tvOS 26.0,
    watchOS 26.0,
    visionOS 26.0,
    macCatalyst 26.0,
    *
)
protocol InlineArrayABIProbe {
    func integers(_ value: InlineArray<2, Int>) -> InlineArray<2, Int>
    func floatingPoint(
        _ value: InlineArray<3, Float>
    ) -> InlineArray<3, Float>
    func empty(_ value: InlineArray<0, Int>) -> InlineArray<0, Int>
    func large(_ value: InlineArray<8, Int>) -> InlineArray<8, Int>
    func references(
        _ value: InlineArray<2, InlineArrayLifetimeToken>
    ) -> InlineArray<2, InlineArrayLifetimeToken>
}

@available(
    macOS 26.0,
    iOS 26.0,
    tvOS 26.0,
    watchOS 26.0,
    visionOS 26.0,
    macCatalyst 26.0,
    *
)
struct RealInlineArrayABIProbe: InlineArrayABIProbe {
    func integers(_ value: InlineArray<2, Int>) -> InlineArray<2, Int> {
        value
    }

    func floatingPoint(
        _ value: InlineArray<3, Float>
    ) -> InlineArray<3, Float> {
        value
    }

    func empty(_ value: InlineArray<0, Int>) -> InlineArray<0, Int> {
        value
    }

    func large(_ value: InlineArray<8, Int>) -> InlineArray<8, Int> {
        value
    }

    func references(
        _ value: InlineArray<2, InlineArrayLifetimeToken>
    ) -> InlineArray<2, InlineArrayLifetimeToken> {
        value
    }
}

@Suite struct InlineArrayABITests {
    @available(
        macOS 26.0,
        iOS 26.0,
        tvOS 26.0,
        watchOS 26.0,
        visionOS 26.0,
        macCatalyst 26.0,
        *
    )
    @Test func smallIntegerValuesRoundTripThroughGPRegisters() throws {
        _ = RealInlineArrayABIProbe()
        let stub = try Stub<any InlineArrayABIProbe>()
        let input: InlineArray<2, Int> = [3, 5]
        let expected: InlineArray<2, Int> = [7, 11]

        stub.when(returning: InlineArray<2, Int>(repeating: 0)) {
            $0.integers(any(using: InlineArray<2, Int>(repeating: 0)))
        }.then { (value: InlineArray<2, Int>) in
            #expect(value[0] == input[0])
            #expect(value[1] == input[1])
            return expected
        }

        let result = stub().integers(input)
        #expect(result[0] == expected[0])
        #expect(result[1] == expected[1])
    }

    @available(
        macOS 26.0,
        iOS 26.0,
        tvOS 26.0,
        watchOS 26.0,
        visionOS 26.0,
        macCatalyst 26.0,
        *
    )
    @Test func homogeneousFloatsRoundTripThroughFPRegisters() throws {
        _ = RealInlineArrayABIProbe()
        let stub = try Stub<any InlineArrayABIProbe>()
        let input: InlineArray<3, Float> = [1.25, -2.5, 4.75]
        let expected: InlineArray<3, Float> = [8.5, 9.25, -10.75]

        stub.when(returning: InlineArray<3, Float>(repeating: 0)) {
            $0.floatingPoint(
                any(using: InlineArray<3, Float>(repeating: 0))
            )
        }.then { (value: InlineArray<3, Float>) in
            #expect(value[0].bitPattern == input[0].bitPattern)
            #expect(value[1].bitPattern == input[1].bitPattern)
            #expect(value[2].bitPattern == input[2].bitPattern)
            return expected
        }

        let result = stub().floatingPoint(input)
        #expect(result[0].bitPattern == expected[0].bitPattern)
        #expect(result[1].bitPattern == expected[1].bitPattern)
        #expect(result[2].bitPattern == expected[2].bitPattern)
    }

    @available(
        macOS 26.0,
        iOS 26.0,
        tvOS 26.0,
        watchOS 26.0,
        visionOS 26.0,
        macCatalyst 26.0,
        *
    )
    @Test func zeroCountValuesRoundTripWithoutRegisters() throws {
        _ = RealInlineArrayABIProbe()
        let stub = try Stub<any InlineArrayABIProbe>()
        let empty: InlineArray<0, Int> = []

        stub.when(returning: empty) {
            $0.empty(any(using: empty))
        }.then { (_: InlineArray<0, Int>) in empty }

        _ = stub().empty(empty)
        stub.verify(returning: empty) {
            $0.empty(any(using: empty))
        }
    }

    @available(
        macOS 26.0,
        iOS 26.0,
        tvOS 26.0,
        watchOS 26.0,
        visionOS 26.0,
        macCatalyst 26.0,
        *
    )
    @Test func largeCopyableValuesUseIndirectArgumentsAndResults() throws {
        _ = RealInlineArrayABIProbe()
        let stub = try Stub<any InlineArrayABIProbe>()
        let input: InlineArray<8, Int> = [1, 2, 3, 4, 5, 6, 7, 8]
        let expected: InlineArray<8, Int> = [8, 7, 6, 5, 4, 3, 2, 1]

        stub.when(returning: InlineArray<8, Int>(repeating: 0)) {
            $0.large(any(using: InlineArray<8, Int>(repeating: 0)))
        }.then { (value: InlineArray<8, Int>) in
            for index in 0 ..< 8 {
                #expect(value[index] == input[index])
            }
            return expected
        }

        let result = stub().large(input)
        for index in 0 ..< 8 {
            #expect(result[index] == expected[index])
        }
    }

    @available(
        macOS 26.0,
        iOS 26.0,
        tvOS 26.0,
        watchOS 26.0,
        visionOS 26.0,
        macCatalyst 26.0,
        *
    )
    @Test func referenceElementsPreserveOwnershipAndIdentity() throws {
        _ = RealInlineArrayABIProbe()
        let stub = try Stub<any InlineArrayABIProbe>()
        weak var firstReference: InlineArrayLifetimeToken?
        weak var secondReference: InlineArrayLifetimeToken?

        do {
            let first = InlineArrayLifetimeToken(id: 1)
            let second = InlineArrayLifetimeToken(id: 2)
            firstReference = first
            secondReference = second
            let input: InlineArray<2, InlineArrayLifetimeToken> = [
                first,
                second
            ]

            stub.when(returning: input) {
                $0.references(any(using: input))
            }.then {
                (value: InlineArray<2, InlineArrayLifetimeToken>) in
                #expect(value[0] === first)
                #expect(value[1] === second)
                return value
            }

            let returned = stub().references(input)
            #expect(returned[0] === first)
            #expect(returned[1] === second)
            stub.reset()
            #expect(firstReference != nil)
            #expect(secondReference != nil)
        }

        #expect(firstReference == nil)
        #expect(secondReference == nil)
    }
}
