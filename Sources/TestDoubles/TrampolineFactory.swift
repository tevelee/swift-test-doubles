#if RUNTIME_STUB
import CTestDoublesTrampoline

enum TrampolineFactory {
    static func make(slot: Int, context: UnsafeRawPointer, isAsync: Bool) -> UnsafeRawPointer? {
        let pointer = isAsync
            ? td_make_async_witness_trampoline(UInt(slot), UInt(bitPattern: context))
            : td_make_witness_trampoline(UInt(slot), UInt(bitPattern: context))
        return pointer.map(UnsafeRawPointer.init)
    }

    static func destroy(_ pointer: UnsafeRawPointer) {
        td_free_witness_trampoline(UnsafeMutableRawPointer(mutating: pointer))
    }
}
#endif // RUNTIME_STUB
