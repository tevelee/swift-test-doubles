#if RUNTIME_STUB
import Echo

/// A protocol requirement that RuntimeStub can route through a runtime stub.
public struct RuntimeStubRequirementDescription: Sendable, CustomStringConvertible {
    /// The witness-table slot index for this requirement.
    public let slot: Int
    /// The kind of requirement, such as `method`, `getter`, or `setter`.
    public let kind: String
    /// The requirement name as reported by Swift metadata or module signatures.
    public let name: String
    /// The argument type spellings used to build an explicit ``Slot``.
    public let argumentTypes: [String]
    /// The return type spelling used to build an explicit ``Slot``.
    public let returnType: String
    /// Whether this requirement uses Swift's throwing convention.
    public let isThrowing: Bool
    /// Whether this requirement uses Swift's async convention.
    public let isAsync: Bool

    /// A readable summary of the requirement.
    public var description: String {
        let effects = [
            isAsync ? "async" : nil,
            isThrowing ? "throws" : nil,
        ].compactMap { $0 }.joined(separator: " ")
        let effectText = effects.isEmpty ? "" : " \(effects)"
        return "\(slot) \(kind) \(name)(\(argumentTypes.joined(separator: ", ")))\(effectText) -> \(returnType)"
    }
}

/// A RuntimeStub-oriented description of a protocol's mockable requirements.
public struct RuntimeStubProtocolDescription: Sendable, CustomStringConvertible {
    /// The protocol name from Swift metadata.
    public let protocolName: String
    /// The mockable requirements in witness-table order.
    public let requirements: [RuntimeStubRequirementDescription]
    /// Copy-pasteable Swift source for explicit ``Slot`` setup.
    public let setupCode: String

    /// A readable report containing requirements and explicit setup source.
    public var description: String {
        var lines = ["RuntimeStub requirements for \(protocolName):"]
        if requirements.isEmpty {
            lines.append("  <no mockable requirements>")
        } else {
            lines += requirements.map { "  \($0.description)" }
        }
        lines.append("")
        lines.append("Explicit setup:")
        lines.append(setupCode)
        return lines.joined(separator: "\n")
    }
}

extension RuntimeStub {
    /// Returns the protocol requirements RuntimeStub can mock and a
    /// copy-pasteable explicit-slot setup scaffold.
    public static func describe(moduleName: String? = nil) throws -> RuntimeStubProtocolDescription {
        let proto = try extractProtocolDescriptor()
        let signatures = try discoverSignaturesForDescription(proto: proto, moduleName: moduleName)
        let requirements = signatures.map(requirementDescription)
        return RuntimeStubProtocolDescription(
            protocolName: proto.name,
            requirements: requirements,
            setupCode: setupScaffold(protocolName: proto.name, requirements: requirements)
        )
    }

    /// Returns a copy-pasteable explicit ``Slot`` setup for the protocol.
    public static func setupScaffold(moduleName: String? = nil) throws -> String {
        try describe(moduleName: moduleName).setupCode
    }

    /// Prints a copy-pasteable explicit ``Slot`` setup for the protocol.
    public static func printSetup(moduleName: String? = nil) throws {
        print(try setupScaffold(moduleName: moduleName))
    }

    /// Inspect environment constraints before creating a stub.
    public static func diagnose() -> RuntimeStubDiagnostics {
        let typeDescription = String(reflecting: P.self)
        let inferredModuleName = inferredModuleName()

        guard let protoDesc = try? extractProtocolDescriptor() else {
            return RuntimeStubDiagnostics(
                typeDescription: typeDescription,
                protocolName: nil,
                inferredModuleName: inferredModuleName,
                hasExistingConformance: false,
                notes: [
                    "Use `RuntimeStub<any YourProtocol>` so the generic type is a protocol existential."
                ]
            )
        }

        let hasExistingConformance = Echo.findConformance(to: protoDesc) != nil
        var notes: [String] = []

        if hasExistingConformance {
            notes.append("A real conformer already exists in the binary — RuntimeStub can use runtime discovery.")
        } else {
            notes.append("No existing conformer was found in the current binary.")
            notes.append("Zero-config RuntimeStub needs a real conformer for signature discovery.")
            notes.append("Use makeFromModule() to extract signatures from the compiled Swift module, or pass explicit Slot/MethodDescriptor values.")
        }

        return RuntimeStubDiagnostics(
            typeDescription: typeDescription,
            protocolName: protoDesc.name,
            inferredModuleName: inferredModuleName,
            hasExistingConformance: hasExistingConformance,
            notes: notes
        )
    }

    private static func discoverSignaturesForDescription(
        proto: ProtocolDescriptor,
        moduleName explicitModuleName: String?
    ) throws -> [DiscoveredSignature] {
        if let conformance = Echo.findConformance(to: proto) {
            return mockableSignatures(from: discoverSignatures(
                witnessTable: conformance.witnessTablePattern,
                proto: conformance.protocol
            ))
        }

        let moduleName: String
        if let explicitModuleName {
            moduleName = explicitModuleName
        } else if let inferred = inferredModuleName() {
            moduleName = inferred
        } else {
            throw RuntimeStubError.moduleNameCouldNotBeInferred(typeDescription: String(reflecting: P.self))
        }
        return try ModuleSignatureDiscovery.discover(
            protocolName: proto.name,
            moduleName: moduleName,
            proto: proto
        )
    }

    private static func requirementDescription(_ signature: DiscoveredSignature) -> RuntimeStubRequirementDescription {
        RuntimeStubRequirementDescription(
            slot: signature.slot,
            kind: requirementKindName(signature.kind),
            name: signature.methodName,
            argumentTypes: signature.qualifiedArgs,
            returnType: signature.qualifiedRet,
            isThrowing: signature.isThrowing,
            isAsync: signature.isAsync
        )
    }

    private static func requirementKindName(_ kind: ProtocolRequirement.Kind) -> String {
        switch kind {
        case .getter:
            return "getter"
        case .setter:
            return "setter"
        case .method:
            return "method"
        case .readCoroutine:
            return "readCoroutine"
        case .modifyCoroutine:
            return "modifyCoroutine"
        case .baseProtocol:
            return "baseProtocol"
        case .associatedTypeAccessFunction:
            return "associatedType"
        case .associatedConformanceAccessFunction:
            return "associatedConformance"
        default:
            return "requirement"
        }
    }

    private static func setupScaffold(
        protocolName: String,
        requirements: [RuntimeStubRequirementDescription]
    ) -> String {
        var lines = ["let stub = try RuntimeStub<any \(protocolName)>.make("]
        if requirements.isEmpty {
            lines.append(")")
            return lines.joined(separator: "\n")
        }

        for (index, requirement) in requirements.enumerated() {
            let comma = index == requirements.count - 1 ? "" : ","
            let expression: String
            if requirement.kind == "getter" {
                expression = ".getter(\(typeExpression(requirement.returnType)))"
            } else {
                let args = requirement.argumentTypes
                    .map(typeExpression)
                    .joined(separator: ", ")
                let throwsArgument = requirement.isThrowing ? ", throws: true" : ""
                let asyncArgument = requirement.isAsync ? ", async: true" : ""
                expression = ".method(args: [\(args)], returns: \(typeExpression(requirement.returnType))\(throwsArgument)\(asyncArgument))"
            }
            lines.append("    \(expression)\(comma) // \(requirement.name)")
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    private static func typeExpression(_ typeName: String) -> String {
        let cleaned = typeName
            .replacingOccurrences(of: "Swift.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch cleaned {
        case "V", "Void", "()":
            return "Void.self"
        case "W1":
            return "Int.self /* FIXME: replace inferred W1 */"
        case "W2":
            return "String.self /* FIXME: replace inferred W2 */"
        case "FX":
            return "Double.self /* FIXME: replace inferred FX */"
        case "INDIRECT":
            return "Never.self /* FIXME: replace inferred indirect type */"
        default:
            return "\(cleaned).self"
        }
    }
}
#endif // RUNTIME_STUB
