import Echo

/// A thunk to install in a witness table slot.
public struct WitnessThunk {
    public let functionPointer: UnsafeRawPointer
    public let requirementIndex: Int

    public init(functionPointer: UnsafeRawPointer, requirementIndex: Int) {
        self.functionPointer = functionPointer
        self.requirementIndex = requirementIndex
    }
}

/// Builds `any Protocol` existential values at runtime by cloning and
/// patching witness tables from existing conformances.
public enum ExistentialBuilder {

    /// Creates a patched witness table by cloning an existing one and
    /// replacing function pointers with the provided thunks.
    public static func patchedWitnessTable(
        cloning witnessTable: WitnessTable,
        with thunks: [WitnessThunk]
    ) -> (witnessTable: WitnessTable, allocation: UnsafeMutableRawPointer) {
        let proto = witnessTable.conformanceDescriptor.protocol
        let totalWords = 1 + proto.numRequirements
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let tableSize = totalWords * wordSize

        let clone = UnsafeMutableRawPointer.allocate(
            byteCount: tableSize,
            alignment: MemoryLayout<UnsafeRawPointer>.alignment
        )
        clone.copyMemory(from: witnessTable.ptr, byteCount: tableSize)

        for thunk in thunks {
            let slotOffset = (1 + thunk.requirementIndex) * wordSize
            (clone + slotOffset).storeBytes(
                of: thunk.functionPointer,
                as: UnsafeRawPointer.self
            )
        }

        return (WitnessTable(ptr: UnsafeRawPointer(clone)), clone)
    }

    /// Constructs an ExistentialContainer from parts.
    public static func buildContainer(
        base: AnyExistentialContainer,
        witnessTable: WitnessTable
    ) -> ExistentialContainer {
        ExistentialContainer(base: base, witnessTable: witnessTable)
    }

    /// Extracts the ExistentialContainer from a pointer to a protocol existential.
    ///
    /// IMPORTANT: Do NOT pass through a generic `<T>` — Swift opens existentials
    /// in generic contexts, losing the container layout. Instead, use this from
    /// a context where you have a concrete existential type.
    ///
    /// Usage: `withUnsafePointer(to: &myProtocolValue) { ExistentialBuilder.extractContainer(from: $0) }`
    public static func extractContainer(from pointer: UnsafeRawPointer) -> ExistentialContainer {
        pointer.load(as: ExistentialContainer.self)
    }

    /// Writes an ExistentialContainer into a pointer to a protocol existential.
    public static func writeContainer(_ container: ExistentialContainer, to pointer: UnsafeMutableRawPointer) {
        pointer.storeBytes(of: container, as: ExistentialContainer.self)
    }
}
