import Echo

package func isIntegerLike(_ type: Any.Type) -> Bool {
    type == Bool.self || isFixedWidthInteger(type)
}

package func isFixedWidthInteger(_ type: Any.Type) -> Bool {
    type == Int.self || type == Int8.self || type == Int16.self || type == Int32.self
        || type == Int64.self || type == UInt.self || type == UInt8.self
        || type == UInt16.self || type == UInt32.self || type == UInt64.self
}

package func isFloatingPoint(_ type: Any.Type) -> Bool {
    type == Float.self || type == Double.self || isFloat16(type)
}

package func isKnownPlaceholderScalar(_ type: Any.Type) -> Bool {
    isFixedWidthInteger(type)
        || type == Bool.self
        || isFloatingPoint(type)
        || type == String.self
}

/// Whether `type` is `Float16`, which transports through floating-point
/// registers like the wider scalars. `Float16` does not exist on Intel Mac
/// targets, where this is always false.
package func isFloat16(_ type: Any.Type) -> Bool {
    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
        return false
    #else
        return type == Float16.self
    #endif
}

/// Returns whether `type` has the Swift runtime function representation.
/// Execution uses this only to reject unsupported forwarding shapes; metadata
/// owns the reflection query itself.
package func isRuntimeFunctionType(_ type: Any.Type) -> Bool {
    reflect(type).kind == .function
}

/// Returns whether `type` is an existential metadata shape.
package func isRuntimeExistentialType(_ type: Any.Type) -> Bool {
    reflect(type) is ExistentialMetadata
}
