import CTestDoublesTrampoline
import Echo
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Discovers method signatures from a witness table using symbol lookup and demangling.
///
/// This works because witness table entries are function pointers to protocol
/// witness thunks whose mangled symbol names encode the full type signature.
func discoverMethods(
    witnessTable: WitnessTable,
    proto: ProtocolDescriptor,
    permitsUnverifiableGetterEffects: Bool = false
) throws -> [MethodDescriptor] {
    let wordSize = MemoryLayout<UnsafeRawPointer>.size
    var results = [MethodDescriptor]()

    for (i, req) in proto.requirements.enumerated() {
        let fnPtr = (witnessTable.ptr + (1 + i) * wordSize).load(as: UnsafeRawPointer.self)

        guard let sname = td_symbol_name(fnPtr) else {
            throw StubError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: i,
                details: "The witness entry has no resolvable symbol. Supply explicit Requirement values."
            )
        }

        let mangledName = String(cString: sname)
        let demangled = demangleSwiftSymbol(mangledName)
        guard let parsed = parseWitnessSignature(demangled, kind: req.flags.kind) else {
            throw StubError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: i,
                details: "Could not parse '\(demangled)'. Supply explicit Requirement values."
            )
        }
        if (parsed.argumentTypeNames + [parsed.returnTypeName]).contains(where: { $0.contains("->") }) {
            throw StubError.unsupportedProtocolShape(
                protocolName: proto.name,
                reason: "Requirement \(i) contains a function argument or result. Use a small hand-written test double for this protocol."
            )
        }

        guard let kind = StubRequirementKind(req.flags.kind) else {
            throw StubError.unsupportedProtocolShape(
                protocolName: proto.name,
                reason: "Requirement \(i) is a \(req.flags.kind). Only instance methods and ordinary getters are supported."
            )
        }
        let isAsync = req.flags.isAsync
        if kind == .getter,
           isAsync,
           permitsUnverifiableGetterEffects == false {
            throw StubError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: i,
                details: "Swift witness symbols do not encode whether an async getter throws. Supply explicit Requirement values for effectful getters."
            )
        }
        let argumentTypes = try parsed.argumentTypeNames.map { name in
            guard let type = resolveRuntimeType(name) else {
                throw StubError.signatureDiscoveryFailed(
                    protocolName: proto.name,
                    requirementIndex: i,
                    details: "Could not resolve runtime metadata for argument type '\(name)'. Supply explicit Requirement values."
                )
            }
            return type
        }
        guard let returnType = resolveRuntimeType(parsed.returnTypeName) else {
            throw StubError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: i,
                details: "Could not resolve runtime metadata for return type '\(parsed.returnTypeName)'. Supply explicit Requirement values."
            )
        }

        results.append(MethodDescriptor(
            kind: kind,
            name: parsed.name,
            index: i,
            argumentTypes: argumentTypes,
            returnType: returnType,
            isThrowing: parsed.isThrowing,
            isAsync: isAsync,
            hasReliableThrowing: kind != .getter
        ))
    }

    return results
}

private extension ProtocolRequirement.Flags {
    var isAsync: Bool { bits & 0x20 != 0 }
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
    let argumentTypeNames: [String]
    let returnTypeName: String
    let isThrowing: Bool
}

private func parseWitnessSignature(
    _ demangled: String,
    kind: ProtocolRequirement.Kind
) -> ParsedWitnessSignature? {
    // Strip "protocol witness for " prefix and " in conformance ..." suffix
    let stripped: String
    if let range = demangled.range(of: " in conformance") {
        stripped = String(demangled[..<range.lowerBound])
            .replacingOccurrences(of: "protocol witness for ", with: "")
    } else {
        stripped = demangled
    }

    let cleaned = stripped

    // Getter: "count.getter : Int"
    if kind == .getter, let getterRange = cleaned.range(of: ".getter : ") {
        guard let propertyName = String(cleaned[..<getterRange.lowerBound])
            .components(separatedBy: ".").last,
              propertyName.isEmpty == false else {
            return nil
        }
        return ParsedWitnessSignature(
            name: propertyName,
            argumentTypeNames: [],
            returnTypeName: normalizeQualifiedType(String(cleaned[getterRange.upperBound...])),
            isThrowing: false
        )
    }

    // Method: "fetch(id: Swift.Int) -> Swift.String"
    // Also handles: "fetch(id: Swift.Int) throws -> Swift.String"
    if let parenOpen = cleaned.firstIndex(of: "("),
       let closeParen = matchingClosingParenthesis(in: cleaned, openingAt: parenOpen) {
        let methodName = extractMethodName(String(cleaned[..<parenOpen]))
        let suffixStart = cleaned.index(after: closeParen)
        if let arrow = cleaned.range(of: " -> ", range: suffixStart..<cleaned.endIndex) {
            let paramsStr = String(cleaned[cleaned.index(after: parenOpen)..<closeParen])
            let parameters = parseParameters(paramsStr)
            let effects = cleaned[suffixStart..<arrow.lowerBound]
            return ParsedWitnessSignature(
                name: buildMethodName(methodName, parameters: parameters),
                argumentTypeNames: parameters.map(\.typeName),
                returnTypeName: normalizeQualifiedType(String(cleaned[arrow.upperBound...])),
                isThrowing: effects.contains("throws")
            )
        }
    }

    return nil
}

private struct ParsedParameter {
    let label: String
    let typeName: String
}

private func parseParameters(_ text: String) -> [ParsedParameter] {
    guard !text.isEmpty else { return [] }
    return topLevelComponents(in: text).map { parameter in
        guard let colon = lastTopLevelColon(in: parameter) else {
            return ParsedParameter(label: "_", typeName: normalizeQualifiedType(parameter))
        }
        let label = parameter[..<colon].trimmingCharacters(in: .whitespaces)
        let typeName = normalizeQualifiedType(String(parameter[parameter.index(after: colon)...]))
        return ParsedParameter(label: label, typeName: typeName)
    }
}

private func buildMethodName(_ baseName: String, parameters: [ParsedParameter]) -> String {
    guard parameters.isEmpty == false else { return "\(baseName)()" }
    let labels = parameters.map { $0.label == "_" ? "_:" : "\($0.label):" }
    return "\(baseName)(\(labels.joined()))"
}

private func extractMethodName(_ str: String) -> String {
    str.components(separatedBy: ".").last ?? str
}

private func normalizeQualifiedType(_ fullType: String) -> String {
    let cleaned = fullType.trimmingCharacters(in: .whitespaces)
    return cleaned == "()" ? "Swift.Void" : cleaned
}

private func matchingClosingParenthesis(
    in text: String,
    openingAt opening: String.Index
) -> String.Index? {
    var depth = 0
    for index in text.indices[opening...] {
        switch text[index] {
        case "(": depth += 1
        case ")":
            depth -= 1
            if depth == 0 { return index }
        default: break
        }
    }
    return nil
}

private func topLevelComponents(in text: String) -> [String] {
    var components: [String] = []
    var start = text.startIndex
    var depths = (parentheses: 0, angles: 0, brackets: 0)
    for index in text.indices {
        switch text[index] {
        case "(": depths.parentheses += 1
        case ")": depths.parentheses -= 1
        case "<": depths.angles += 1
        case ">": depths.angles -= 1
        case "[": depths.brackets += 1
        case "]": depths.brackets -= 1
        case "," where depths.parentheses == 0 && depths.angles == 0 && depths.brackets == 0:
            components.append(String(text[start..<index]).trimmingCharacters(in: .whitespaces))
            start = text.index(after: index)
        default: break
        }
    }
    components.append(String(text[start...]).trimmingCharacters(in: .whitespaces))
    return components
}

private func lastTopLevelColon(in text: String) -> String.Index? {
    var candidate: String.Index?
    var depths = (parentheses: 0, angles: 0, brackets: 0)
    for index in text.indices {
        switch text[index] {
        case "(": depths.parentheses += 1
        case ")": depths.parentheses -= 1
        case "<": depths.angles += 1
        case ">": depths.angles -= 1
        case "[": depths.brackets += 1
        case "]": depths.brackets -= 1
        case ":" where depths.parentheses == 0 && depths.angles == 0 && depths.brackets == 0:
            candidate = index
        default: break
        }
    }
    return candidate
}

private func resolveRuntimeType(_ name: String) -> Any.Type? {
    switch name {
    case "V", "Void", "Swift.Void", "()": return Void.self
    case "Int", "Swift.Int": return Int.self
    case "Int8", "Swift.Int8": return Int8.self
    case "Int16", "Swift.Int16": return Int16.self
    case "Int32", "Swift.Int32": return Int32.self
    case "Int64", "Swift.Int64": return Int64.self
    case "UInt", "Swift.UInt": return UInt.self
    case "UInt8", "Swift.UInt8": return UInt8.self
    case "UInt16", "Swift.UInt16": return UInt16.self
    case "UInt32", "Swift.UInt32": return UInt32.self
    case "UInt64", "Swift.UInt64": return UInt64.self
    case "Bool", "Swift.Bool": return Bool.self
    case "String", "Swift.String": return String.self
    case "Character", "Swift.Character": return Character.self
    case "Double", "Swift.Double": return Double.self
    case "Float", "Swift.Float": return Float.self
    case "[String]", "[Swift.String]", "Array<String>", "Swift.Array<Swift.String>":
        return [String].self
    case "[Int]", "[Swift.Int]", "Array<Int>", "Swift.Array<Swift.Int>":
        return [Int].self
    case "[Double]", "[Swift.Double]", "Array<Double>", "Swift.Array<Swift.Double>":
        return [Double].self
    default:
        if let type = _typeByName(name) {
            return type
        }
        if let tupleElements = parsedTupleElements(name) {
            let elementTypes = tupleElements.compactMap { resolveRuntimeType($0.typeName) }
            guard elementTypes.count == tupleElements.count else { return nil }
            return tupleType(
                elementTypes,
                labels: tupleElements.map(\.label)
            )
        }
        if name.hasSuffix("?"),
           let wrapped = resolveRuntimeType(String(name.dropLast())) {
            return _openExistential(wrapped, do: optionalType)
        }
        if let argument = genericArgument(in: name, constructors: ["Optional", "Swift.Optional"]),
           let wrapped = resolveRuntimeType(argument) {
            return _openExistential(wrapped, do: optionalType)
        }
        if let argument = genericArgument(in: name, constructors: ["Array", "Swift.Array"]),
           let element = resolveRuntimeType(argument) {
            return _openExistential(element, do: arrayType)
        }
        if name.hasSuffix(".Type"),
           let instance = resolveRuntimeType(String(name.dropLast(5))) {
            return _openExistential(instance, do: metatypeType)
        }
        if name.hasPrefix("any "),
           let existential = _typeByName(String(name.dropFirst(4))) {
            return existential
        }
        if !name.contains("."), let type = _typeByName("Swift.\(name)") {
            return type
        }
        if let type = swiftTypeByNominalName(name) {
            return type
        }
        return swiftTypeByMangledName(name)
    }
}

private struct ParsedTupleElement {
    let label: String?
    let typeName: String
}

private func parsedTupleElements(_ name: String) -> [ParsedTupleElement]? {
    guard name.first == "(", name.last == ")" else { return nil }
    let contents = String(name.dropFirst().dropLast())
    guard contents.isEmpty == false else { return [] }
    return topLevelComponents(in: contents).map { element in
        guard let colon = lastTopLevelColon(in: element) else {
            return ParsedTupleElement(label: nil, typeName: element)
        }
        return ParsedTupleElement(
            label: String(element[..<colon]).trimmingCharacters(in: .whitespaces),
            typeName: String(element[element.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        )
    }
}

private func tupleType(_ elements: [Any.Type], labels: [String?]) -> Any.Type? {
    guard elements.count == 2 || elements.count == 3 else { return nil }
    let labelPointer = TupleLabelPool.shared.pointer(for: labels)
    switch elements.count {
    case 0:
        return Void.self
    case 2:
        let response = td_swift_get_tuple_type_metadata2(
            0,
            reflect(elements[0]).ptr,
            reflect(elements[1]).ptr,
            labelPointer
        )
        guard let metadata = response.metadata else { return nil }
        return unsafeBitCast(metadata, to: Any.Type.self)
    case 3:
        let response = td_swift_get_tuple_type_metadata3(
            0,
            reflect(elements[0]).ptr,
            reflect(elements[1]).ptr,
            reflect(elements[2]).ptr,
            labelPointer
        )
        guard let metadata = response.metadata else { return nil }
        return unsafeBitCast(metadata, to: Any.Type.self)
    default:
        preconditionFailure("Tuple arity was validated before metadata lookup.")
    }
}

private final class TupleLabelPool: @unchecked Sendable {
    static let shared = TupleLabelPool()

    private let lock = NSLock()
    private var pointers: [String: UnsafePointer<CChar>] = [:]

    func pointer(for labels: [String?]) -> UnsafePointer<CChar>? {
        guard labels.contains(where: { $0 != nil }) else { return nil }
        let value = labels.map { $0 ?? "" }.joined(separator: " ") + " "
        lock.lock()
        defer { lock.unlock() }
        if let pointer = pointers[value] { return pointer }
        guard let pointer = strdup(value) else { return nil }
        // Tuple metadata retains the label address as a uniquing key.
        let immutable = UnsafePointer(pointer)
        pointers[value] = immutable
        return immutable
    }
}

private func genericArgument(in name: String, constructors: [String]) -> String? {
    for constructor in constructors {
        let prefix = "\(constructor)<"
        guard name.hasPrefix(prefix), name.last == ">" else { continue }
        return String(name.dropFirst(prefix.count).dropLast())
    }
    return nil
}

private func optionalType<Wrapped>(of _: Wrapped.Type) -> Any.Type {
    Optional<Wrapped>.self
}

private func arrayType<Element>(of _: Element.Type) -> Any.Type {
    Array<Element>.self
}

private func metatypeType<Instance>(of _: Instance.Type) -> Any.Type {
    Instance.Type.self
}

private func swiftTypeByNominalName(_ name: String) -> Any.Type? {
    let parts = name.split(separator: ".").map(String.init)
    guard parts.count == 2 else { return nil }
    let module = parts[0]
    let typeName = parts[1]
    let prefix = "\(module.utf8.count)\(module)\(typeName.utf8.count)\(typeName)"
    for suffix in ["V", "O", "C"] {
        if let type = swiftTypeByMangledName(prefix + suffix) {
            return type
        }
    }
    return nil
}

private func swiftTypeByMangledName(_ name: String) -> Any.Type? {
    guard let swiftGetTypeByMangledNameInContext else {
        return nil
    }
    return name.utf8CString.withUnsafeBufferPointer { buffer -> Any.Type? in
        guard let base = buffer.baseAddress else { return nil }
        guard let metadata = swiftGetTypeByMangledNameInContext(
            UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
            UInt(name.utf8.count),
            nil,
            nil
        ) else {
            return nil
        }
        return unsafeBitCast(metadata, to: Any.Type.self)
    }
}

private typealias SwiftGetTypeByMangledNameInContext = @convention(c) (
    UnsafePointer<UInt8>,
    UInt,
    UnsafeRawPointer?,
    UnsafeRawPointer?
) -> UnsafeRawPointer?

private let swiftGetTypeByMangledNameInContext: SwiftGetTypeByMangledNameInContext? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "swift_getTypeByMangledNameInContext") else {
        return nil
    }
    return unsafeBitCast(symbol, to: SwiftGetTypeByMangledNameInContext.self)
}()
