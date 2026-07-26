import Echo

/// Stable metadata queries shared by signature discovery and ABI execution.
package func functionHasTypedThrows(_ metadata: FunctionMetadata) -> Bool {
    metadata.extendedFlags?.isTypedThrows == true
}

package func typedThrownErrorType(_ metadata: FunctionMetadata) -> Any.Type? {
    guard functionHasTypedThrows(metadata) else { return nil }

    #if os(Linux) && arch(x86_64)
        return nil
    #else
        return metadata.thrownErrorType
    #endif
}
