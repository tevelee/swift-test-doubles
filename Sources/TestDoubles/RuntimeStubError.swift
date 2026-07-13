#if RUNTIME_STUB
public struct RuntimeStubDiagnostics: Sendable, CustomStringConvertible {
    public let typeDescription: String
    public let protocolName: String?
    public let inferredModuleName: String?
    public let hasExistingConformance: Bool
    public let notes: [String]

    public init(
        typeDescription: String,
        protocolName: String?,
        inferredModuleName: String?,
        hasExistingConformance: Bool,
        notes: [String]
    ) {
        self.typeDescription = typeDescription
        self.protocolName = protocolName
        self.inferredModuleName = inferredModuleName
        self.hasExistingConformance = hasExistingConformance
        self.notes = notes
    }

    public var description: String {
        var lines = [
            "type: \(typeDescription)",
            "protocol: \(protocolName ?? "unknown")",
            "inferred module: \(inferredModuleName ?? "unavailable")",
            "existing conformance in binary: \(hasExistingConformance ? "yes" : "no")",
        ]

        if !notes.isEmpty {
            lines.append("notes:")
            lines.append(contentsOf: notes.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}

public enum RuntimeStubError: Error, Sendable, CustomStringConvertible {
    case typeIsNotProtocol(typeDescription: String)
    case noConformanceFound(protocolName: String, typeDescription: String)
    case moduleNameCouldNotBeInferred(typeDescription: String)
    case slotCountMismatch(protocolName: String, expected: Int, actual: Int)
    case runtimeCompilerFailed(protocolName: String, moduleName: String, details: String?)
    case missingCompiledSymbol(protocolName: String, symbol: String)
    case trampolineAllocationFailed(slot: Int)
    @available(*, deprecated, message: "RuntimeStub supports async requirements.")
    case unsupportedAsyncRequirement(protocolName: String, methodName: String)
    case unsupportedFunctionValue(protocolName: String, methodName: String)
    case unsupportedTypeKind(typeName: String)
    case invalidRequirementIndex(protocolName: String, index: Int, requirementCount: Int)
    case duplicateRequirementIndex(protocolName: String, index: Int)
    case moduleSignatureDiscoveryFailed(protocolName: String, moduleName: String, details: String)
    case moduleSignatureNotFound(protocolName: String, moduleName: String)

    public var description: String {
        switch self {
        case .typeIsNotProtocol(let typeDescription):
            return "Could not extract a protocol from '\(typeDescription)'. Use `RuntimeStub<any YourProtocol>`."
        case .noConformanceFound(let protocolName, _):
            return """
            No conformance found for protocol '\(protocolName)' in the current binary. \
            Zero-config RuntimeStub needs one for signature discovery. \
            Use makeFromModule() to extract signatures from the compiled Swift module, pass explicit Slot/MethodDescriptor values, or use CompiledStub when you want generated full-fidelity conformers.
            """
        case .moduleNameCouldNotBeInferred(let typeDescription):
            return """
            Could not infer the module name for '\(typeDescription)'. \
            Pass `moduleName:` explicitly.
            """
        case .slotCountMismatch(let protocolName, let expected, let actual):
            return "Expected \(expected) mockable slots for '\(protocolName)', got \(actual)."
        case .runtimeCompilerFailed(let protocolName, let moduleName, let details):
            var base = "RuntimeCompiler failed for '\(protocolName)' in module '\(moduleName)'."
            if let details, !details.isEmpty {
                base += "\n\(details)"
            }
            return base
        case .missingCompiledSymbol(let protocolName, let symbol):
            return "Compiled mock for '\(protocolName)' is missing exported symbol '\(symbol)'."
        case .trampolineAllocationFailed(let slot):
            return "Could not allocate an executable trampoline veneer for slot \(slot)."
        case .unsupportedAsyncRequirement(let protocolName, let methodName):
            return """
            Obsolete async-requirement error for '\(methodName)' on '\(protocolName)'. \
            RuntimeStub now supports async requirements.
            """
        case .unsupportedFunctionValue(let protocolName, let methodName):
            return """
            RuntimeStub cannot safely marshal function values for '\(methodName)' on '\(protocolName)'. \
            Protocol witnesses use compiler-generated closure reabstraction thunks. \
            Use CompiledStub or ManualStub for this requirement.
            """
        case .unsupportedTypeKind(let typeName):
            return "Unsupported type kind for '\(typeName)'."
        case .invalidRequirementIndex(let protocolName, let index, let requirementCount):
            return "Requirement index \(index) is outside '\(protocolName)' requirement range 0..<\(requirementCount)."
        case .duplicateRequirementIndex(let protocolName, let index):
            return "Requirement index \(index) was described more than once for '\(protocolName)'."
        case .moduleSignatureDiscoveryFailed(let protocolName, let moduleName, let details):
            return """
            Failed to extract symbol graph signatures for '\(protocolName)' from module '\(moduleName)'.
            \(details)
            """
        case .moduleSignatureNotFound(let protocolName, let moduleName):
            return "Could not find protocol '\(protocolName)' in the symbol graph for module '\(moduleName)'."
        }
    }
}
#endif
