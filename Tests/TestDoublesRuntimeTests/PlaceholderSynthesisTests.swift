import Testing
@testable import TestDoublesRuntime

private struct PlaceholderElement: Equatable, Hashable, Sendable {
    let id: Int
}

private struct PlaceholderAggregate: Equatable {
    let count: Int
    let label: String
    let values: [Int]
}

private enum PlaceholderChoice: Equatable {
    case none
    case value(Int)
}

private final class UnsupportedPlaceholder {}

@Suite struct PlaceholderSynthesisTests {
    @Test func scalarPlaceholdersUseValidZeroValues() {
        #expect(PlaceholderValue.make(Int.self) == 0)
        #expect(PlaceholderValue.make(Bool.self) == false)
        #expect(PlaceholderValue.make(Double.self) == 0)
        #expect(PlaceholderValue.make(String.self) == "")
    }

    @Test func collectionPlaceholdersAreEmptyForArbitraryElements() {
        #expect(PlaceholderValue.make([UInt8].self) == [])
        #expect(PlaceholderValue.make([PlaceholderElement].self) == [])
        #expect(PlaceholderValue.make(Set<String>.self) == [])
        #expect(PlaceholderValue.make([String: Int].self) == [:])
        #expect(PlaceholderValue.make([PlaceholderElement: [Int]].self) == [:])
    }

    @Test func aggregateAndEnumPlaceholdersAreFullyInitialized() {
        #expect(
            PlaceholderValue.make(PlaceholderAggregate.self)
                == PlaceholderAggregate(count: 0, label: "", values: [])
        )
        #expect(PlaceholderValue.make((Int, String).self)?.0 == 0)
        #expect(PlaceholderValue.make((Int, String).self)?.1 == "")
        #expect(
            PlaceholderValue.make(PlaceholderChoice.self)
                == PlaceholderChoice.none
        )
    }

    @Test func metatypePlaceholdersPreserveTheirInstanceType() {
        #expect(PlaceholderValue.make(Int.Type.self) == Int.self)
        #expect(PlaceholderValue.make((any Error).Type.self) == (any Error).self)
    }

    @Test func unsupportedTypesFailBeforeInitializingStorage() {
        #expect(PlaceholderValue.canInitialize(type: UnsupportedPlaceholder.self) == false)
        #expect(PlaceholderValue.make(UnsupportedPlaceholder.self) == nil)
        #expect(PlaceholderValue.canInitialize(type: ((Int) -> Int).self) == false)
        #expect(PlaceholderValue.make(((Int) -> Int).self) == nil)
    }

    @Test func dummySynthesisAddsFunctionValuesWithoutChangingRecordingPlaceholders() {
        typealias SwiftFunction = (Int, String) -> Bool
        typealias AsyncThrowingFunction = @Sendable (Int) async throws -> String
        typealias ThinFunction = @convention(thin) (Int) -> Int
        typealias CFunction = @convention(c) (Int32) -> Int32

        #expect(DummyValue.make(SwiftFunction.self) != nil)
        #expect(DummyValue.make(AsyncThrowingFunction.self) != nil)
        #expect(DummyValue.make(ThinFunction.self) != nil)
        #expect(DummyValue.make(CFunction.self) != nil)
        #if canImport(ObjectiveC)
            typealias BlockFunction = @convention(block) (Int) -> Int
            #expect(DummyValue.make(BlockFunction.self) != nil)
        #endif
        #expect(PlaceholderValue.make(SwiftFunction.self) == nil)
    }
}
