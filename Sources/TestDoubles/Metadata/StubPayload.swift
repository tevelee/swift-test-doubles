/// The concrete payload stored inside fabricated protocol existentials.
///
/// Metadata and recording only need an opaque owner whose lifetime follows the
/// generated value. Runtime-specific resources remain behind that ownership
/// boundary.
final class StubPayload {
    let owner: AnyObject

    init(resources: AnyObject) {
        owner = resources
    }
}
