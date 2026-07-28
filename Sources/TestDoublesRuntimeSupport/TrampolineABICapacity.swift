import CTestDoublesTrampoline

/// Capacities of the C frame slots that the Swift runtime may encode directly.
///
/// Keep these projections tied to the C header: the assembly bridge owns the
/// physical frame, while Metadata and Runtime both consume these limits.
package enum TrampolineABICapacity {
    package static let directReturnRegisterCount =
        Int(TD_DIRECT_RETURN_REGISTER_COUNT)
}
