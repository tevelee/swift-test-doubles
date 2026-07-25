/// The concrete payload stored inside fabricated protocol existentials.
///
/// Metadata and recording only need an opaque owner whose lifetime follows the
/// generated value. Runtime-specific resources remain behind that ownership
/// boundary.
package final class FabricatedPayload {
    package let owner: AnyObject

    package init(resources: AnyObject) {
        owner = resources
    }
}
