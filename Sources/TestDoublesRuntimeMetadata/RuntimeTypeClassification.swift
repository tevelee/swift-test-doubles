func isIntegerLike(_ type: Any.Type) -> Bool {
    type == Bool.self || isFixedWidthInteger(type)
}

func isFixedWidthInteger(_ type: Any.Type) -> Bool {
    type == Int.self || type == Int8.self || type == Int16.self || type == Int32.self
        || type == Int64.self || type == UInt.self || type == UInt8.self
        || type == UInt16.self || type == UInt32.self || type == UInt64.self
}

func isFloatingPoint(_ type: Any.Type) -> Bool {
    type == Float.self || type == Double.self || isFloat16(type)
}

func isKnownPlaceholderScalar(_ type: Any.Type) -> Bool {
    isFixedWidthInteger(type)
        || type == Bool.self
        || isFloatingPoint(type)
        || type == String.self
}

/// Whether `type` is `Float16`, which transports through floating-point
/// registers like the wider scalars. `Float16` does not exist on Intel Mac
/// targets, where this is always false.
func isFloat16(_ type: Any.Type) -> Bool {
    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
        return false
    #else
        return type == Float16.self
    #endif
}
