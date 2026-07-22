enum ProtocolWitnessTableLayout {
    /// Returns the address of a protocol requirement's witness-table entry.
    /// The first word is the conformance descriptor, so requirement zero
    /// begins one pointer-sized word after the table address.
    static func entry(
        at witnessIndex: Int,
        in witnessTable: UnsafeRawPointer
    ) -> UnsafeRawPointer {
        witnessTable
            + (1 + witnessIndex) * MemoryLayout<UnsafeRawPointer>.size
    }

    static func entry(
        at witnessIndex: Int,
        in witnessTable: UnsafeMutableRawPointer
    ) -> UnsafeMutableRawPointer {
        witnessTable
            + (1 + witnessIndex) * MemoryLayout<UnsafeRawPointer>.size
    }
}
