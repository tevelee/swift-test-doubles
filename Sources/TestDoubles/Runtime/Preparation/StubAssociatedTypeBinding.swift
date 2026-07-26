extension Stub {
    /// A concrete runtime binding for an associated type of an unbound protocol existential.
    public struct AssociatedTypeBinding: Sendable {
        let protocolType: Any.Type
        let name: String
        let type: Any.Type

        /// Binds one associated type declared by `protocolType` to `type`.
        ///
        /// The declaring protocol is part of the binding identity, so
        /// compositions may bind equally named associated types independently.
        public static func binding(
            declaredBy protocolType: Any.Type,
            named name: String,
            to type: Any.Type
        ) -> Self {
            Self(protocolType: protocolType, name: name, type: type)
        }
    }
}
