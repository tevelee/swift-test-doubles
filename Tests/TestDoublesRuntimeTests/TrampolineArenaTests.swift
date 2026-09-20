@testable import TestDoublesRuntime
import Testing

@Suite("Witness veneer arena")
struct TrampolineArenaTests {
    @Test func concurrentPageReuseExecutesTheCurrentInvocation() async throws {
        // Recycling executable addresses across threads must not reuse a
        // Rosetta translation containing an earlier arena's invocation.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for worker in 0 ..< 16 {
                group.addTask {
                    let identity: @convention(c) (UInt) -> UInt = { $0 }
                    let target = unsafeBitCast(identity, to: UnsafeRawPointer.self)
                    for iteration in 0 ..< 1_024 {
                        let expected = UInt(worker * 1_024 + iteration + 1)
                        let invocation = try #require(UnsafeRawPointer(bitPattern: expected))
                        let arena = try #require(TrampolineFactory.Arena())
                        let entry = try #require(
                            arena.makeTyped(
                                target: target,
                                invocation: invocation,
                                invocationArgumentIndex: 0
                            )
                        )
                        try #require(arena.publish())
                        let call = unsafeBitCast(entry, to: (@convention(c) (UInt) -> UInt).self)
                        let actual = call(0)
                        #expect(actual == expected)
                        arena.destroy()
                    }
                }
            }
            try await group.waitForAll()
        }
    }

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
        #expect(arena.isPublished)
        #expect(arena.publish() == false)
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

    @Test func `rejects invalid typed register indexes without poisoning arena`() throws {
        let context = UnsafeMutableRawPointer.allocate(
            byteCount: 32,
            alignment: MemoryLayout<UInt>.alignment,
        )
        defer { context.deallocate() }
        let arena = try #require(TrampolineFactory.Arena())
        let target = try #require(
            arena.make(
                kind: .synchronous,
                slot: 0,
                context: UnsafeRawPointer(context)
            )
        )

        #expect(
            arena.makeTyped(
                target: target,
                invocation: UnsafeRawPointer(context),
                invocationArgumentIndex: -1
            ) == nil
        )
        #expect(
            arena.makeTyped(
                target: target,
                invocation: UnsafeRawPointer(context),
                invocationArgumentIndex: RuntimeArchitecture.current
                    .generalPurposeArgumentRegisterCount
            ) == nil
        )
        #expect(arena.publish())
    }

    @Test func `destroy is idempotent and terminal`() throws {
        let context = UnsafeMutableRawPointer.allocate(
            byteCount: 32,
            alignment: MemoryLayout<UInt>.alignment,
        )
        defer { context.deallocate() }
        let arena = try #require(TrampolineFactory.Arena())
        _ = try #require(
            arena.make(
                kind: .synchronous,
                slot: 0,
                context: UnsafeRawPointer(context)
            )
        )

        arena.destroy()
        arena.destroy()

        #expect(arena.pageCount == 0)
        #expect(arena.isPublished == false)
        #expect(arena.publish() == false)
        #expect(
            arena.make(
                kind: .synchronous,
                slot: 1,
                context: UnsafeRawPointer(context)
            ) == nil
        )
    }
}
