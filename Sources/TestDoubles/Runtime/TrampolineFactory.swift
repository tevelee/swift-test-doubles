import CTestDoublesTrampoline

enum TrampolineFactory {
    enum Kind {
        case synchronous
        case asynchronous
        case modify
        case read(resumeDiscriminator: UInt16)
    }

    /// Builds one fabricated witness graph's veneers before publishing all of
    /// its executable pages together.
    final class Arena {
        private enum State {
            case building(OpaquePointer)
            case published(OpaquePointer)
            case failed(OpaquePointer)
            case destroyed

            var rawArena: OpaquePointer? {
                switch self {
                    case .building(let rawArena),
                        .published(let rawArena),
                        .failed(let rawArena):
                        return rawArena
                    case .destroyed:
                        return nil
                }
            }
        }

        private var state: State

        init?() {
            guard let rawArena = td_witness_veneer_arena_create() else {
                return nil
            }
            state = .building(rawArena)
        }

        deinit {
            destroy()
        }

        var isPublished: Bool {
            guard case .published = state else { return false }
            return true
        }

        var pageCount: Int {
            guard let rawArena = state.rawArena else { return 0 }
            return Int(td_witness_veneer_arena_page_count(rawArena))
        }

        func make(
            kind: Kind,
            slot: Int,
            context: UnsafeRawPointer
        ) -> UnsafeRawPointer? {
            guard case .building(let rawArena) = state else { return nil }
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
                case .read(let resumeDiscriminator):
                    pointer = td_witness_veneer_arena_make_read(
                        rawArena,
                        UInt(slot),
                        UInt(bitPattern: context),
                        resumeDiscriminator
                    )
            }
            return pointer.map(UnsafeRawPointer.init)
        }

        func makeTyped(
            target: UnsafeRawPointer,
            invocation: UnsafeRawPointer,
            invocationArgumentIndex: Int
        ) -> UnsafeRawPointer? {
            guard case .building(let rawArena) = state,
                invocationArgumentIndex >= 0,
                invocationArgumentIndex
                    < RuntimeArchitecture.current
                    .generalPurposeArgumentRegisterCount
            else {
                return nil
            }
            return td_witness_veneer_arena_make_typed(
                rawArena,
                target,
                UInt(bitPattern: invocation),
                UInt(invocationArgumentIndex)
            ).map(UnsafeRawPointer.init)
        }

        func publish() -> Bool {
            guard case .building(let rawArena) = state else {
                return false
            }
            guard td_witness_veneer_arena_publish(rawArena) else {
                state = .failed(rawArena)
                return false
            }
            state = .published(rawArena)
            return true
        }

        func destroy() {
            guard let rawArena = state.rawArena else { return }
            state = .destroyed
            td_witness_veneer_arena_destroy(rawArena)
        }
    }
}
