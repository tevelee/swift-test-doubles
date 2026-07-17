import CTestDoublesTrampoline

enum TrampolineFactory {
    enum Kind {
        case synchronous
        case asynchronous
        case modify
    }

    /// Builds one fabricated witness graph's veneers before publishing all of
    /// its executable pages together.
    final class Arena {
        private var rawArena: OpaquePointer?
        private(set) var isPublished = false

        init?() {
            guard let rawArena = td_witness_veneer_arena_create() else {
                return nil
            }
            self.rawArena = rawArena
        }

        deinit {
            destroy()
        }

        var pageCount: Int {
            guard let rawArena else { return 0 }
            return Int(td_witness_veneer_arena_page_count(rawArena))
        }

        func make(
            kind: Kind,
            slot: Int,
            context: UnsafeRawPointer
        ) -> UnsafeRawPointer? {
            guard let rawArena, isPublished == false else { return nil }
            let pointer: UnsafeMutableRawPointer?
            switch kind {
                case .synchronous:
                    pointer = td_witness_veneer_arena_make_witness(
                        rawArena,
                        UInt(slot),
                        UInt(bitPattern: context)
                    )
                case .asynchronous:
                    pointer = td_witness_veneer_arena_make_async(
                        rawArena,
                        UInt(slot),
                        UInt(bitPattern: context)
                    )
                case .modify:
                    pointer = td_witness_veneer_arena_make_modify(
                        rawArena,
                        UInt(slot),
                        UInt(bitPattern: context)
                    )
            }
            return pointer.map(UnsafeRawPointer.init)
        }

        func makeTyped(
            target: UnsafeRawPointer,
            invocation: UnsafeRawPointer,
            invocationArgumentIndex: Int
        ) -> UnsafeRawPointer? {
            guard let rawArena, isPublished == false else { return nil }
            return td_witness_veneer_arena_make_typed(
                rawArena,
                target,
                UInt(bitPattern: invocation),
                UInt(invocationArgumentIndex)
            ).map(UnsafeRawPointer.init)
        }

        func publish() -> Bool {
            guard let rawArena, isPublished == false,
                td_witness_veneer_arena_publish(rawArena)
            else {
                return false
            }
            isPublished = true
            return true
        }

        func destroy() {
            guard let rawArena else { return }
            td_witness_veneer_arena_destroy(rawArena)
            self.rawArena = nil
        }
    }
}
