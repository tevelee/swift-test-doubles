import EchoRuntimeReflection

/// Construction-time closure transport selected for one concrete function
/// value. Keeping the reflected signature, bridge analysis, discriminator, and
/// fallback thunk here avoids rebuilding them for every invocation.
package struct PreparedFunctionReabstraction: @unchecked Sendable {
    enum Execution {
        case copy
        case dynamic(FunctionBridgePlan, discriminator: UInt16)
        case thunk(UnsafeRawPointer, discriminator: UInt16)
        case unsupported(String)
    }

    let type: Any.Type
    let function: FunctionTypeInfo
    let execution: Execution
}
