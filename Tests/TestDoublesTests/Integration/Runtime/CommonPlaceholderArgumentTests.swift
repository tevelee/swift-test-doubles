import Testing
import TestDoubles

private enum CommonPlaceholderArgumentError: Error {
    case expected
}

protocol StaticStringPlaceholderProbe {
    func inspect(_ value: StaticString) -> Int
}

protocol AnyHashablePlaceholderProbe {
    func inspect(_ value: AnyHashable) -> String
}

protocol ErrorPlaceholderProbe {
    func inspect(_ value: any Error) -> String
}

protocol CollectionPlaceholderProbe {
    func slice(_ value: ArraySlice<Int>) -> Int
    func contiguous(_ value: ContiguousArray<Int>) -> Int
    func sequence(_ value: AnySequence<Int>) -> Int
    func iterator(_ value: AnyIterator<Int>) -> Int
    func collection(_ value: AnyCollection<Int>) -> Int
    func bidirectional(_ value: AnyBidirectionalCollection<Int>) -> Int
    func randomAccess(_ value: AnyRandomAccessCollection<Int>) -> Int
}

struct LiveStaticStringPlaceholderProbe: StaticStringPlaceholderProbe {
    func inspect(_ value: StaticString) -> Int { 0 }
}

struct LiveAnyHashablePlaceholderProbe: AnyHashablePlaceholderProbe {
    func inspect(_ value: AnyHashable) -> String { "" }
}

struct LiveErrorPlaceholderProbe: ErrorPlaceholderProbe {
    func inspect(_ value: any Error) -> String { "" }
}

struct LiveCollectionPlaceholderProbe: CollectionPlaceholderProbe {
    func slice(_ value: ArraySlice<Int>) -> Int { 0 }
    func contiguous(_ value: ContiguousArray<Int>) -> Int { 0 }
    func sequence(_ value: AnySequence<Int>) -> Int { 0 }
    func iterator(_ value: AnyIterator<Int>) -> Int { 0 }
    func collection(_ value: AnyCollection<Int>) -> Int { 0 }
    func bidirectional(_ value: AnyBidirectionalCollection<Int>) -> Int { 0 }
    func randomAccess(_ value: AnyRandomAccessCollection<Int>) -> Int { 0 }
}

struct CommonPlaceholderArgumentTests {
    @Test func staticStringRecordsWithoutAFixture() throws {
        let stub = try Stub<any StaticStringPlaceholderProbe>()
        stub.when { $0.inspect(Match.any()) }.thenReturn(6)

        #expect(stub().inspect("actual") == 6)
    }

    @Test func anyHashableRecordsWithoutAFixture() throws {
        let stub = try Stub<any AnyHashablePlaceholderProbe>()
        stub.when { $0.inspect(Match.any()) }
            .then { (value: AnyHashable) in String(describing: value) }

        #expect(stub().inspect(AnyHashable("metadata")) == "metadata")
    }

    @Test func emptyCollectionWrappersRecordWithoutElementFixtures() throws {
        let stub = try Stub<any CollectionPlaceholderProbe>()
        stub.when { $0.slice(Match.any()) }.thenReturn(6)
        stub.when { $0.contiguous(Match.any()) }
            .then { (value: ContiguousArray<Int>) in value.reduce(0, +) }
        stub.when { $0.sequence(Match.any()) }
            .then { (value: AnySequence<Int>) in value.reduce(0, +) }
        stub.when { $0.iterator(Match.any()) }
            .then { (value: AnyIterator<Int>) in value.next() ?? -1 }
        stub.when { $0.collection(Match.any()) }
            .then { (value: AnyCollection<Int>) in value.reduce(0, +) }
        stub.when { $0.bidirectional(Match.any()) }
            .then { (value: AnyBidirectionalCollection<Int>) in value.reduce(0, +) }
        stub.when { $0.randomAccess(Match.any()) }
            .then { (value: AnyRandomAccessCollection<Int>) in value.reduce(0, +) }

        var source = [11].makeIterator()
        let iterator = AnyIterator { source.next() }
        #expect(stub().slice([1, 2, 3][...]) == 6)
        #expect(stub().contiguous(ContiguousArray([4, 5])) == 9)
        #expect(stub().sequence(AnySequence([6, 7])) == 13)
        #expect(stub().iterator(iterator) == 11)
        #expect(stub().collection(AnyCollection([8, 9])) == 17)
        #expect(stub().bidirectional(AnyBidirectionalCollection([10, 11])) == 21)
        #expect(stub().randomAccess(AnyRandomAccessCollection([12, 13])) == 25)
    }

    @Test func errorExistentialRecordsWithoutASentinelFixture() throws {
        let stub = try Stub<any ErrorPlaceholderProbe>()
        stub.when { $0.inspect(Match.any()) }
            .then { (value: any Error) in String(describing: value) }

        #expect(stub().inspect(CommonPlaceholderArgumentError.expected) == "expected")
    }
}
