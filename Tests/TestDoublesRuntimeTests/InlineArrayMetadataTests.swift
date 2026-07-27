import Echo
import TestDoublesFixtures
import Testing
@testable import TestDoublesRuntimeMetadata

@Suite struct InlineArrayMetadataTests {
    @available(macOS 26.0, *)
    @Test func integerSpecializationsResolveExactMetadata() {
        expectMetadata(
            named: "Swift.InlineArray<0, Swift.Int>",
            equals: InlineArray<0, Int>.self
        )
        expectMetadata(
            named: "Swift.InlineArray<1, Swift.Int>",
            equals: InlineArray<1, Int>.self
        )
        expectMetadata(
            named: "Swift.InlineArray<3, Swift.Int>",
            equals: InlineArray<3, Int>.self
        )
        expectMetadata(
            named: "Swift.InlineArray<64, Swift.Int>",
            equals: InlineArray<64, Int>.self
        )
    }

    @available(macOS 26.0, *)
    @Test func floatingPointSpecializationsResolveExactMetadata() {
        expectMetadata(
            named: "Swift.InlineArray<3, Swift.Float>",
            equals: InlineArray<3, Float>.self
        )
        expectMetadata(
            named: "Swift.InlineArray<4, Swift.Double>",
            equals: InlineArray<4, Double>.self
        )
    }

    @Test func malformedAndUnsupportedValueSpellingsFailClosed() {
        for name in [
            "Swift.InlineArray<-1, Swift.Int>",
            "Swift.InlineArray<+1, Swift.Int>",
            "Swift.InlineArray<03, Swift.Int>",
            "Swift.InlineArray<1_0, Swift.Int>",
            "Swift.InlineArray<3.0, Swift.Int>",
            "Swift.InlineArray<three, Swift.Int>",
            "Swift.InlineArray<9223372036854775808, Swift.Int>",
            "Swift.InlineArray<18446744073709551616, Swift.Int>",
            "Swift.InlineArray<Swift.Int, 3>",
            "Swift.InlineArray<3>",
            "Swift.InlineArray<3, Swift.Int, Swift.String>"
        ] {
            #expect(resolveRuntimeType(name) == nil)
        }
    }

    @Test func noncopyableElementsFailClosed() {
        _ = ExternalMoveOnlyValue.self
        #expect(
            resolveRuntimeType(
                "Swift.InlineArray<3, TestDoublesFixtures.ExternalMoveOnlyValue>"
            ) == nil
        )
    }

    @available(macOS 26.0, *)
    @Test func fixedStorageClassifiesIntegerAndZeroCounts() {
        guard case .void = abiClass(for: InlineArray<0, Int>.self) else {
            Issue.record("Expected an empty InlineArray to have void ABI storage.")
            return
        }
        guard
            case .integer(let oneWord) = abiClass(
                for: InlineArray<1, Int>.self
            )
        else {
            Issue.record("Expected one Int element in one GP register.")
            return
        }
        #expect(oneWord == 1)
        guard
            case .integer(let twoWords) = abiClass(
                for: InlineArray<2, Int>.self
            )
        else {
            Issue.record("Expected two Int elements in two GP registers.")
            return
        }
        #expect(twoWords == 2)
    }

    @available(macOS 26.0, *)
    @Test func fixedStorageClassifiesHomogeneousFloatingPointElements() {
        guard
            case .aggregate(let parts) = abiClass(
                for: InlineArray<3, Float>.self
            )
        else {
            Issue.record("Expected a three-register homogeneous FP aggregate.")
            return
        }
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.register == .fp })
        #expect(parts.map(\.offset) == [0, 4, 8])
        #expect(parts.allSatisfy { $0.byteCount == 4 })
    }

    @available(macOS 26.0, *)
    @Test func largeFixedStorageFallsBackToIndirectTransport() {
        guard case .indirect = abiClass(for: InlineArray<8, Int>.self) else {
            Issue.record("Expected a large InlineArray argument to be indirect.")
            return
        }
        guard
            case .indirect = abiClass(
                for: InlineArray<8, Int>.self,
                isReturn: true
            )
        else {
            Issue.record("Expected a large InlineArray result to be indirect.")
            return
        }
    }

    private func expectMetadata(
        named name: String,
        equals expected: Any.Type
    ) {
        guard let resolved = resolveRuntimeType(name) else {
            Issue.record("Could not resolve \(name).")
            return
        }
        #expect(ObjectIdentifier(resolved) == ObjectIdentifier(expected))
        #expect(inlineArrayHasCopyableElements(resolved))
    }
}
