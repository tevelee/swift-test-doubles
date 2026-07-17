@testable import TestDoubles
import Testing

@Suite("Witness veneer arena")
struct TrampolineArenaTests {
    @Test func `batches aligned witness veneer kinds into one page`() throws {
        let context = UnsafeMutableRawPointer.allocate(
            byteCount: 32,
            alignment: MemoryLayout<UInt>.alignment,
        )
        defer { context.deallocate() }
        let arena = try #require(TrampolineFactory.Arena())

        let synchronous = try #require(
            arena.make(
                kind: .synchronous,
                slot: 3,
                context: UnsafeRawPointer(context)
            ),
        )

        let asynchronous = try #require(
            arena.make(
                kind: .asynchronous,
                slot: 7,
                context: UnsafeRawPointer(context)
            ),
        )

        let modify = try #require(
            arena.make(
                kind: .modify,
                slot: 11,
                context: UnsafeRawPointer(context)
            )
        )
        let typed = try #require(
            arena.makeTyped(
                target: synchronous,
                invocation: UnsafeRawPointer(context),
                invocationArgumentIndex: 0
            )
        )
        let entries = [synchronous, asynchronous, modify, typed]

        #expect(Set(entries.map { UInt(bitPattern: $0) }).count == entries.count)
        #expect(entries.allSatisfy { UInt(bitPattern: $0).isMultiple(of: 16) })
        #expect(arena.pageCount == 1)
        #expect(arena.publish())
        #expect(
            arena.make(
                kind: .modify,
                slot: 11,
                context: UnsafeRawPointer(context)
            ) == nil
        )
    }

    @Test func `chains overflow pages before publishing`() throws {
        let context = UnsafeMutableRawPointer.allocate(
            byteCount: 32,
            alignment: MemoryLayout<UInt>.alignment,
        )
        defer { context.deallocate() }
        let arena = try #require(TrampolineFactory.Arena())

        var entries: Set<UInt> = []
        for slot in 0 ..< 1_024 {
            let entry = try #require(
                arena.make(
                    kind: .synchronous,
                    slot: slot,
                    context: UnsafeRawPointer(context)
                )
            )
            entries.insert(UInt(bitPattern: entry))
        }

        #expect(entries.count == 1_024)
        #expect(arena.pageCount > 1)
        #expect(arena.publish())
    }
}
