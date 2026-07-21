import CTestDoublesTrampoline

/// Typed access to the C call-frame storage populated by the assembly bridge.
///
/// The C layout remains the source of truth. Keeping every byte offset here
/// prevents the Swift codecs from depending directly on frame representation.
struct TrampolineCallFrame {
    static let generalPurposeReturnCount = 4
    static let floatingPointReturnCount = 4

    private enum Offset {
        static let slot = Int(TD_FRAME_SLOT_OFFSET)
        static let context = Int(TD_FRAME_CONTEXT_OFFSET)
        static let generalPurpose = Int(TD_FRAME_GP_OFFSET)
        static let floatingPoint = Int(TD_FRAME_FP_OFFSET)
        static let stackPointer = Int(TD_FRAME_STACK_POINTER_OFFSET)
        static let indirectResult = Int(TD_FRAME_INDIRECT_RESULT_OFFSET)
        static let swiftSelf = Int(TD_FRAME_SWIFT_SELF_OFFSET)
        static let swiftError = Int(TD_FRAME_SWIFT_ERROR_OFFSET)
        static let returnGeneralPurpose = Int(TD_FRAME_RETURN_GP_OFFSET)
        static let returnFloatingPoint = Int(TD_FRAME_RETURN_FP_OFFSET)
        static let returnError = Int(TD_FRAME_RETURN_ERROR_OFFSET)
    }

    #if arch(x86_64)
        static let generalPurposeArgumentLimit = 6
    #else
        static let generalPurposeArgumentLimit = 8
    #endif
    static let floatingPointArgumentLimit = 8

    let pointer: UnsafeMutablePointer<TDCallFrame>

    init(_ pointer: UnsafeMutablePointer<TDCallFrame>) {
        self.pointer = pointer
    }

    var snapshot: TDCallFrame { pointer.pointee }

    var slot: Int { Int(loadWord(at: Offset.slot)) }

    var context: UInt { loadWord(at: Offset.context) }

    var incomingSwiftError: UInt { loadWord(at: Offset.swiftError) }

    var indirectResultAddress: UInt { loadWord(at: Offset.indirectResult) }

    var swiftSelfAddress: UInt { loadWord(at: Offset.swiftSelf) }

    var returnedError: UInt { loadWord(at: Offset.returnError) }

    func restore(_ snapshot: TDCallFrame) {
        pointer.pointee = snapshot
    }

    func scalarBits(at location: CallFrameArgumentLocation) -> UInt64 {
        precondition(
            location.byteCount <= MemoryLayout<UInt64>.size,
            "[TestDoubles] Scalar call-frame decoding cannot read a wider vector lane."
        )
        return switch location.storage {
            case .generalPurposeRegister(let index):
                UInt64(generalPurposeWord(index))
            case .vectorRegister(let index):
                floatingPointLowWord(index)
            case .stack(let byteOffset):
                UInt64(stackWord(byteOffset: byteOffset))
        }
    }

    func storeGeneralPurposeReturn(_ value: UInt, at index: Int = 0) {
        storeWord(value, at: Offset.returnGeneralPurpose + index * 8)
    }

    func storeGeneralPurposeArgument(_ value: UInt, at index: Int) {
        precondition(index < Self.generalPurposeArgumentLimit)
        storeWord(value, at: Offset.generalPurpose + index * 8)
    }

    func storeFloatingPointArgument(_ value: UInt64, at index: Int) {
        precondition(index < Self.floatingPointArgumentLimit)
        storeWord(UInt(value), at: Offset.floatingPoint + index * 16)
    }

    func storeIndirectResultAddress(_ value: UInt) {
        storeWord(value, at: Offset.indirectResult)
    }

    func storeFloatingPointReturn(_ value: UInt, at index: Int = 0) {
        storeWord(value, at: Offset.returnFloatingPoint + index * 8)
    }

    func storeReturnError(_ value: UInt) {
        storeWord(value, at: Offset.returnError)
    }

    func zeroReturn() {
        for index in 0 ..< Self.generalPurposeReturnCount {
            storeGeneralPurposeReturn(0, at: index)
        }
        for index in 0 ..< Self.floatingPointReturnCount {
            storeFloatingPointReturn(0, at: index)
        }
    }

    private var raw: UnsafeMutableRawPointer { UnsafeMutableRawPointer(pointer) }

    private func loadWord(at offset: Int) -> UInt {
        raw.loadUnaligned(fromByteOffset: offset, as: UInt.self)
    }

    private func storeWord(_ value: UInt, at offset: Int) {
        raw.storeBytes(of: value, toByteOffset: offset, as: UInt.self)
    }

    private func generalPurposeWord(_ index: Int) -> UInt {
        loadWord(at: Offset.generalPurpose + index * 8)
    }

    private func floatingPointLowWord(_ index: Int) -> UInt64 {
        raw.loadUnaligned(
            fromByteOffset: Offset.floatingPoint + index * 16,
            as: UInt64.self
        )
    }

    private func stackWord(byteOffset: Int) -> UInt {
        let address = loadWord(at: Offset.stackPointer)
        guard let stack = UnsafeRawPointer(bitPattern: address) else {
            preconditionFailure(
                "[TestDoubles] Trampoline captured an invalid stack pointer."
            )
        }
        return stack.loadUnaligned(fromByteOffset: byteOffset, as: UInt.self)
    }
}
