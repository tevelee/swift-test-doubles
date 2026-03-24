import Echo
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Discovered signature for a protocol requirement.
struct DiscoveredSignature {
    let slot: Int
    let kind: ProtocolRequirement.Kind
    let methodName: String
    let args: [String]
    let ret: String
    let isThrowing: Bool
    let rawDemangled: String
    let paramLabels: [String]

    init(slot: Int, kind: ProtocolRequirement.Kind, methodName: String, args: [String], ret: String,
         isThrowing: Bool = false, rawDemangled: String = "", paramLabels: [String] = []) {
        self.slot = slot
        self.kind = kind
        self.methodName = methodName
        self.args = args
        self.ret = ret
        self.isThrowing = isThrowing
        self.rawDemangled = rawDemangled
        self.paramLabels = paramLabels
    }

    var methodSignature: MethodSignature {
        MethodSignature(args: args, ret: ret)
    }
}

/// Discovers method signatures from a witness table using dladdr + demangling.
///
/// This works because witness table entries are function pointers to protocol
/// witness thunks whose mangled symbol names encode the full type signature.
func discoverSignatures(
    witnessTable: WitnessTable,
    proto: ProtocolDescriptor
) -> [DiscoveredSignature] {
    let wordSize = MemoryLayout<UnsafeRawPointer>.size
    var results = [DiscoveredSignature]()

    for (i, req) in proto.requirements.enumerated() {
        let fnPtr = (witnessTable.ptr + (1 + i) * wordSize).load(as: UnsafeRawPointer.self)

        var info = Dl_info()
        guard dladdr(fnPtr, &info) != 0, let sname = info.dli_sname else {
            results.append(DiscoveredSignature(
                slot: i, kind: req.flags.kind, methodName: "slot_\(i)", args: [], ret: "Int"
            ))
            continue
        }

        let mangledName = String(cString: sname)
        let demangled = demangleSwiftSymbol(mangledName)
        let parsed = parseWitnessSignature(demangled, kind: req.flags.kind)

        results.append(DiscoveredSignature(
            slot: i,
            kind: req.flags.kind,
            methodName: parsed.name,
            args: parsed.args,
            ret: parsed.ret,
            isThrowing: demangled.contains(") throws ->"),
            rawDemangled: demangled,
            paramLabels: parsed.labels
        ))
    }

    return results
}

// MARK: - Swift demangling

private func demangleSwiftSymbol(_ mangledName: String) -> String {
    mangledName.utf8CString.withUnsafeBufferPointer { buf in
        guard let ptr = buf.baseAddress else { return mangledName }
        guard let result = swift_demangle(
            mangledName: ptr,
            mangledNameLength: buf.count - 1,
            outputBuffer: nil,
            outputBufferSize: nil,
            flags: 0
        ) else {
            return mangledName
        }
        defer { free(result) }
        return String(cString: result)
    }
}

@_silgen_name("swift_demangle")
private func swift_demangle(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: Int,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<Int>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?

// MARK: - Signature parsing

private struct ParsedWitnessSignature {
    let name: String
    let args: [String]
    let ret: String
    let labels: [String]
}

private func parseWitnessSignature(_ demangled: String, kind: ProtocolRequirement.Kind) -> ParsedWitnessSignature {
    // Strip "protocol witness for " prefix and " in conformance ..." suffix
    let stripped: String
    if let range = demangled.range(of: " in conformance") {
        stripped = String(demangled[..<range.lowerBound])
            .replacingOccurrences(of: "protocol witness for ", with: "")
    } else {
        stripped = demangled
    }

    // Remove module qualifiers: "ModuleName.TypeName." → ""
    // Find the last component that looks like a method
    let cleaned = removeModulePrefixes(stripped)

    // Getter: "count.getter : Int"
    if kind == .getter, let getterRange = cleaned.range(of: ".getter : ") {
        let propName = String(cleaned[..<getterRange.lowerBound])
            .components(separatedBy: ".").last ?? "unknown"
        let retType = simplifyType(String(cleaned[getterRange.upperBound...]))
        return ParsedWitnessSignature(name: propName, args: [], ret: retType, labels: [])
    }

    // Setter: "count.setter : Int"
    if kind == .setter, let setterRange = cleaned.range(of: ".setter : ") {
        let propName = String(cleaned[..<setterRange.lowerBound])
            .components(separatedBy: ".").last ?? "unknown"
        let retType = simplifyType(String(cleaned[setterRange.upperBound...]))
        return ParsedWitnessSignature(name: propName, args: [retType], ret: "Void", labels: ["newValue"])
    }

    // Method: "fetch(id: Swift.Int) -> Swift.String"
    // Also handles: "fetch(id: Swift.Int) throws -> Swift.String"
    if let parenOpen = cleaned.firstIndex(of: "(") {
        let methodName = extractMethodName(String(cleaned[..<parenOpen]))

        // Match both ") -> " and ") throws -> "
        let arrowPatterns = [") throws -> ", ") -> "]
        var arrowRange: Range<String.Index>?
        for pattern in arrowPatterns {
            if let range = cleaned.range(of: pattern) {
                arrowRange = range
                break
            }
        }

        if let arrow = arrowRange {
            let paramsStr = String(cleaned[cleaned.index(after: parenOpen)..<arrow.lowerBound])
            let retType = simplifyType(String(cleaned[arrow.upperBound...]))
            let args = parseParams(paramsStr)
            let labels = parseLabels(paramsStr)
            let fullName = buildMethodName(methodName, params: paramsStr)
            return ParsedWitnessSignature(name: fullName, args: args, ret: retType, labels: labels)
        } else if let closeParen = cleaned.firstIndex(of: ")") {
            // No return type → Void
            let paramsStr = String(cleaned[cleaned.index(after: parenOpen)..<closeParen])
            let args = parseParams(paramsStr)
            let labels = parseLabels(paramsStr)
            let fullName = buildMethodName(methodName, params: paramsStr)
            return ParsedWitnessSignature(name: fullName, args: args, ret: "Void", labels: labels)
        }
    }

    return ParsedWitnessSignature(name: "unknown", args: [], ret: "Int", labels: [])
}

private func parseLabels(_ paramsStr: String) -> [String] {
    guard !paramsStr.isEmpty else { return [] }
    return paramsStr.components(separatedBy: ", ").map { param in
        let parts = param.components(separatedBy: ": ")
        return parts.count >= 2 ? parts[0].trimmingCharacters(in: .whitespaces) : "_"
    }
}

private func parseParams(_ paramsStr: String) -> [String] {
    guard !paramsStr.isEmpty else { return [] }
    return paramsStr.components(separatedBy: ", ").map { param in
        let parts = param.components(separatedBy: ": ")
        return simplifyType(parts.last ?? param)
    }
}

private func buildMethodName(_ baseName: String, params: String) -> String {
    guard !params.isEmpty else { return "\(baseName)()" }
    let labels = params.components(separatedBy: ", ").map { param in
        let parts = param.components(separatedBy: ": ")
        if parts.count >= 2 {
            let label = parts[0].trimmingCharacters(in: .whitespaces)
            return label == "_" ? "_:" : "\(label):"
        }
        return "_:"
    }
    return "\(baseName)(\(labels.joined()))"
}

private func extractMethodName(_ str: String) -> String {
    str.components(separatedBy: ".").last ?? str
}

private func removeModulePrefixes(_ str: String) -> String {
    // Remove "ModuleName." prefixes from types but preserve the structure
    // This is a simplified heuristic
    str.replacingOccurrences(of: "Swift.", with: "")
}

private func simplifyType(_ fullType: String) -> String {
    let cleaned = fullType
        .replacingOccurrences(of: "Swift.", with: "")
        .trimmingCharacters(in: .whitespaces)
    // Normalize "()" to "Void"
    return cleaned == "()" ? "Void" : cleaned
}
