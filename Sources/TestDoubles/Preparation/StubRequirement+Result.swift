extension Stub.Requirement.Value {
    /// Describes a Result whose success and failure use requirement value schemas.
    ///
    /// The resolved failure type must conform to `Error`.
    public static func result(success: Self, failure: Self) -> Self {
        Self(
            source: .result(
                success: success.source,
                failure: failure.source
            ),
            ownership: nil
        )
    }
}
