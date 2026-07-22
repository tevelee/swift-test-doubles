import Echo

func functionLoweredParameterCount(_ metadata: FunctionMetadata) -> Int {
    metadata.flags.numParams + (metadata.isNonisolatedNonsending ? 1 : 0)
}

/// Echo's zero-parameter accessor uses an unsafe-uninitialized empty Array,
/// which writes shared empty-array bookkeeping and trips ThreadSanitizer when
/// nested `() -> T` metadata is inspected concurrently.
func safeFunctionParameterTypes(
    _ metadata: FunctionMetadata
) -> [Any.Type] {
    guard metadata.flags.numParams > 0 else { return [] }
    return metadata.paramTypes
}

func loweredFunctionParameterType(
    _ metadata: FunctionMetadata,
    type: Any.Type,
    at index: Int
) -> Any.Type {
    guard metadata.flags.hasParamFlags,
        metadata.paramFlags[index].isVariadic
    else {
        return type
    }
    func arrayType<Element>(of type: Element.Type) -> Any.Type {
        [Element].self
    }
    return _openExistential(type, do: arrayType)
}

func functionParameterOwnership(
    _ metadata: FunctionMetadata,
    at index: Int
) -> UInt32 {
    guard metadata.flags.hasParamFlags else { return 0 }
    return UInt32(metadata.paramFlags[index].valueOwnership.rawValue)
}

func functionParameterIsIsolated(
    _ metadata: FunctionMetadata,
    at index: Int
) -> Bool {
    guard metadata.flags.hasParamFlags else { return false }
    return metadata.paramFlags[index].bits & 0x400 != 0
}

func functionIsAsync(_ metadata: FunctionMetadata) -> Bool {
    metadata.flags.bits & 0x2000_0000 != 0
}
