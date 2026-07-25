enum ProtocolWitnessTableLayout {
    /// `WitnessTableFirstRequirementOffset` (include/swift/ABI/MetadataValues.h):
    /// word 0 of a witness table is the conformance descriptor, so requirement
    /// N lives at word `1 + N`.
    static let firstRequirementOffset = 1

    /// Returns the address of a protocol requirement's witness-table entry.
    /// The first word is the conformance descriptor, so requirement zero
    /// begins one pointer-sized word after the table address.
    static func entry(
        at witnessIndex: Int,
        in witnessTable: UnsafeRawPointer
    ) -> UnsafeRawPointer {
        witnessTable
            + (firstRequirementOffset + witnessIndex) * MemoryLayout<UnsafeRawPointer>.size
    }

    static func entry(
        at witnessIndex: Int,
        in witnessTable: UnsafeMutableRawPointer
    ) -> UnsafeMutableRawPointer {
        witnessTable
            + (firstRequirementOffset + witnessIndex) * MemoryLayout<UnsafeRawPointer>.size
    }
}
