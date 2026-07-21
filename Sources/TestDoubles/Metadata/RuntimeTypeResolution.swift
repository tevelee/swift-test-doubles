import CTestDoublesTrampoline
import Echo
import Foundation

func resolveRuntimeType(_ name: String) -> Any.Type? {
    guard let syntax = DemangledTypeSyntax(name) else { return nil }
    return resolveRuntimeType(syntax)
}

func resolveRuntimeType(_ syntax: DemangledTypeSyntax) -> Any.Type? {
    RuntimeSymbols.cachedRuntimeType(named: syntax.canonicalSpelling) {
        resolveUncachedRuntimeType(syntax)
    }
}

private func resolveUncachedRuntimeType(_ syntax: DemangledTypeSyntax) -> Any.Type? {
    let name = syntax.canonicalSpelling
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
        case "Error", "Swift.Error": return (any Error).self
        #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
            case "Float16", "Swift.Float16": return Float16.self
        #endif
        default: return resolveCompositeRuntimeType(syntax)
    }
}

private func resolveCompositeRuntimeType(_ syntax: DemangledTypeSyntax) -> Any.Type? {
    let name = syntax.canonicalSpelling
    if let type = _typeByName(name) {
        return type
    }
    if case .function(let function) = syntax,
        let type = functionType(function)
    {
        return type
    }
    if let tupleElements = parsedTupleElements(name) {
        let elementTypes = tupleElements.compactMap {
            resolveRuntimeType($0.typeName)
        }
        guard elementTypes.count == tupleElements.count else { return nil }
        return tupleType(elementTypes, labels: tupleElements.map(\.label))
    }
    if name.hasSuffix("?"),
        let wrapped = resolveRuntimeType(String(name.dropLast()))
    {
        return _openExistential(wrapped, do: optionalType)
    }
    if let argument = genericArgument(
        in: name,
        constructors: ["Optional", "Swift.Optional"]
    ), let wrapped = resolveRuntimeType(argument) {
        return _openExistential(wrapped, do: optionalType)
    }
    if let argument = genericArgument(
        in: name,
        constructors: ["Array", "Swift.Array"]
    ), let element = resolveRuntimeType(argument) {
        return _openExistential(element, do: arrayType)
    }
    if let argument = genericArgument(
        in: name,
        constructors: ["Set", "Swift.Set"]
    ), let element = resolveRuntimeType(argument), let set = setType(of: element) {
        return set
    }
    if let type = twoArgumentGenericType(name) {
        return type
    }
    if let type = genericNominalType(named: name) {
        return type
    }
    if let collection = bracketCollectionType(name) {
        return collection
    }
    if name.hasSuffix(".Type"),
        let instance = resolveRuntimeType(String(name.dropLast(5)))
    {
        return _openExistential(instance, do: metatypeType)
    }
    if name.hasPrefix("any "),
        let existential = _typeByName(String(name.dropFirst(4)))
    {
        return existential
    }
    if !name.contains("."), let type = _typeByName("Swift.\(name)") {
        return type
    }
    return swiftTypeByNominalName(name) ?? swiftTypeByMangledName(name)
}

private func twoArgumentGenericType(_ name: String) -> Any.Type? {
    if let arguments = genericArgument(
        in: name,
        constructors: ["Result", "Swift.Result"]
    ) {
        if let components = topLevelComponents(in: arguments),
            components.count == 2,
            let success = resolveRuntimeType(components[0]),
            let failure = resolveRuntimeType(components[1])
        {
            return resultType(success: success, failure: failure)
        }
    }
    if let arguments = genericArgument(
        in: name,
        constructors: ["Dictionary", "Swift.Dictionary"]
    ) {
        if let components = topLevelComponents(in: arguments),
            components.count == 2,
            let key = resolveRuntimeType(components[0]),
            let value = resolveRuntimeType(components[1])
        {
            return dictionaryType(key: key, value: value)
        }
    }
    return nil
}

/// Recovers nested function escaping from the raw symbol mangling. Swift's
/// human-readable demangler omits this distinction, while the type mangling
/// retains it (`XE` denotes a noescape function type).
func resolveRuntimeType(
    _ syntax: DemangledTypeSyntax,
    containedInMangledSymbol mangledSymbol: String
) -> Any.Type? {
    guard case .function(let function) = syntax else {
        return resolveRuntimeType(syntax)
    }
    let variants = [false, true].compactMap {
        functionType(
            function,
            nestedFunctionParametersEscape: $0
        )
    }
    var unique: [Any.Type] = []
    for type in variants
    where unique.contains(where: {
        ObjectIdentifier($0) == ObjectIdentifier(type)
    }) == false {
        unique.append(type)
    }
    let matches = unique.filter {
        guard let typeName = _mangledTypeName($0) else { return false }
        return mangledSymbol.contains(typeName)
    }
    // `XE` is Swift's noescape-function mangling. A top-level noescape closure
    // may carry a stack context and cannot cross retained `Any` storage. An
    // escaping outer closure may safely accept a noescape callback, however:
    // that callback exists only for the duration of the outer invocation. Only
    // accept that shape when one reconstructed type matches exactly and every
    // noescape marker belongs to an occurrence of that type's mangling.
    if mangledSymbol.contains("XE") {
        guard matches.count == 1,
            let typeName = _mangledTypeName(matches[0]),
            noescapeMarkers(in: mangledSymbol, areCoveredBy: typeName)
        else {
            return nil
        }
        return matches[0]
    }
    if matches.count == 1 {
        return matches[0]
    }
    let linkedVariants = unique.filter(FunctionReabstraction.hasLinkedThunks)
    if linkedVariants.count == 1 {
        return linkedVariants[0]
    }
    return unique.count == 1 ? unique[0] : nil
}

private func noescapeMarkers(
    in mangledSymbol: String,
    areCoveredBy typeMangle: String
) -> Bool {
    let symbol = Array(mangledSymbol.utf8)
    let type = Array(typeMangle.utf8)
    guard type.isEmpty == false else { return false }

    var covered = Array(repeating: false, count: symbol.count)
    if type.count <= symbol.count {
        for start in 0 ... (symbol.count - type.count)
        where symbol[start ..< start + type.count].elementsEqual(type) {
            for index in start ..< start + type.count {
                covered[index] = true
            }
        }
    }
    guard symbol.count >= 2 else { return true }
    for index in 0 ..< (symbol.count - 1)
    where symbol[index] == Character("X").asciiValue
        && symbol[index + 1] == Character("E").asciiValue
        && !(covered[index] && covered[index + 1])
    {
        return false
    }
    return true
}

private struct ParsedFunctionType {
    let parameterTypes: [Any.Type]
    let parameterFlags: [UInt32]
    let resultType: Any.Type
    let flags: UInt
    let extendedFlags: UInt32
    let thrownErrorType: Any.Type?
    let globalActorType: Any.Type?
}

/// Builds the canonical metadata Swift itself uses for a concrete function
/// type. `_typeByName` intentionally does not accept demangled function
/// spellings, while witness symbols expose only those spellings.
private func functionType(
    _ syntax: DemangledFunctionTypeSyntax,
    escapingByDefault: Bool = true,
    nestedFunctionParametersEscape: Bool = false
) -> Any.Type? {
    guard
        let parsed = parsedFunctionType(
            syntax,
            escapingByDefault: escapingByDefault,
            nestedFunctionParametersEscape: nestedFunctionParametersEscape
        )
    else {
        return nil
    }
    let parameters = parsed.parameterTypes.map { reflect($0).ptr }
    return parameters.withUnsafeBufferPointer { buffer -> Any.Type? in
        parsed.parameterFlags.withUnsafeBufferPointer { flagBuffer -> Any.Type? in
            let parameterFlags =
                parsed.parameterFlags.contains(where: { $0 != 0 })
                ? flagBuffer.baseAddress
                : nil
            let metadata: UnsafeRawPointer?
            if parsed.extendedFlags != 0 {
                guard let swiftGetExtendedFunctionTypeMetadata else { return nil }
                metadata = swiftGetExtendedFunctionTypeMetadata(
                    parsed.flags,
                    0,
                    buffer.baseAddress,
                    parameterFlags,
                    reflect(parsed.resultType).ptr,
                    parsed.globalActorType.map { reflect($0).ptr },
                    parsed.extendedFlags,
                    parsed.thrownErrorType.map { reflect($0).ptr }
                )
            } else if let globalActorType = parsed.globalActorType {
                guard let swiftGetFunctionTypeMetadataGlobalActor else {
                    return nil
                }
                metadata = swiftGetFunctionTypeMetadataGlobalActor(
                    parsed.flags,
                    0,
                    buffer.baseAddress,
                    parameterFlags,
                    reflect(parsed.resultType).ptr,
                    reflect(globalActorType).ptr
                )
            } else {
                guard let swiftGetFunctionTypeMetadata else { return nil }
                metadata = swiftGetFunctionTypeMetadata(
                    parsed.flags,
                    buffer.baseAddress,
                    parameterFlags,
                    reflect(parsed.resultType).ptr
                )
            }
            guard let metadata else { return nil }
            return unsafeBitCast(metadata, to: Any.Type.self)
        }
    }
}

private func parsedFunctionType(
    _ syntax: DemangledFunctionTypeSyntax,
    escapingByDefault: Bool = true,
    nestedFunctionParametersEscape: Bool = false
) -> ParsedFunctionType? {
    let attributes = syntax.attributes
    guard functionAttributesAreSupported(attributes) else { return nil }
    let typedThrownError: Any.Type?
    if let thrownError = syntax.effects.thrownError {
        guard let type = resolveRuntimeType(thrownError) else { return nil }
        typedThrownError = type
    } else {
        typedThrownError = nil
    }
    guard let resultType = resolveRuntimeType(syntax.result) else { return nil }
    let parsedParameters = syntax.parameters.compactMap {
        parseFunctionParameter(
            $0.canonicalSpelling,
            nestedFunctionParametersEscape: nestedFunctionParametersEscape
        )
    }
    guard parsedParameters.count == syntax.parameters.count else { return nil }
    let parameterTypes = parsedParameters.map(\.type)
    let parameterFlags = parsedParameters.map(\.flags)

    let convention = functionConvention(in: attributes)
    var flags = UInt(parameterTypes.count) | (UInt(convention.rawValue) << 16)
    if parameterFlags.contains(where: { $0 != 0 }) {
        flags |= 0x0200_0000
    }
    var extendedFlags = UInt32(0)
    let globalActorType = functionGlobalActorType(in: attributes)
    if convention == .swift
        && (escapingByDefault
            || attributes.split(separator: " ").contains("@escaping"))
    {
        flags |= 0x0400_0000
    }
    if attributes.split(separator: " ").contains("@Sendable") {
        flags |= 0x4000_0000
    }
    if attributes.split(separator: " ").contains("@isolated(any)") {
        flags |= 0x8000_0000
        extendedFlags |= 0x2
    }
    if attributes.split(separator: " ").contains("nonisolated(nonsending)") {
        flags |= 0x8000_0000
        extendedFlags |= 0x4
    }
    if globalActorType != nil {
        flags |= 0x1000_0000
    }
    if syntax.effects.isThrowing {
        flags |= 0x0100_0000
    }
    if syntax.effects.isAsync {
        flags |= 0x2000_0000
    }
    if typedThrownError != nil {
        flags |= 0x8000_0000
        extendedFlags |= 0x1
    }
    if syntax.hasSendingResult {
        flags |= 0x8000_0000
        extendedFlags |= 0x10
    }
    return ParsedFunctionType(
        parameterTypes: parameterTypes,
        parameterFlags: parameterFlags,
        resultType: resultType,
        flags: flags,
        extendedFlags: extendedFlags,
        thrownErrorType: typedThrownError,
        globalActorType: globalActorType
    )
}

private func parseFunctionParameter(
    _ spelling: String,
    nestedFunctionParametersEscape: Bool
) -> (type: Any.Type, flags: UInt32)? {
    var value = spelling.trimmingCharacters(in: .whitespaces)
    var flags = UInt32(0)
    if value.hasPrefix("isolated ") {
        flags |= 0x400
        value.removeFirst("isolated ".count)
    }
    if value.hasPrefix("sending ") {
        flags |= 0x800
        value.removeFirst("sending ".count)
    }
    let ownershipPrefixes: [(String, UInt32)] = [
        ("inout ", 1), ("borrowing ", 2), ("__shared ", 2),
        ("consuming ", 3), ("__owned ", 3)
    ]
    for (prefix, ownership) in ownershipPrefixes where value.hasPrefix(prefix) {
        flags |= ownership
        value.removeFirst(prefix.count)
        break
    }
    if value.hasPrefix("@autoclosure ") {
        flags |= 0x100
        value.removeFirst("@autoclosure ".count)
    }
    if value.hasSuffix("...") {
        flags |= 0x80
        value.removeLast(3)
    }
    guard let syntax = DemangledTypeSyntax(value) else { return nil }
    let type: Any.Type?
    if case .function(let function) = syntax {
        type = functionType(
            function,
            escapingByDefault: nestedFunctionParametersEscape,
            nestedFunctionParametersEscape: nestedFunctionParametersEscape
        )
    } else {
        type = resolveRuntimeType(syntax)
    }
    return type.map { ($0, flags) }
}

private func functionAttributesAreSupported(_ attributes: String) -> Bool {
    attributes.split(separator: " ").allSatisfy {
        $0 == "@Sendable" || $0 == "@escaping" || $0 == "@isolated(any)"
            || $0 == "@convention(c)" || $0 == "@convention(block)"
            || $0 == "nonisolated(nonsending)"
            || functionGlobalActorType(in: String($0)) != nil
    }
}

private func functionConvention(in attributes: String) -> FunctionConvention {
    let values = attributes.split(separator: " ")
    if values.contains("@convention(c)") { return .c }
    if values.contains("@convention(block)") { return .block }
    return .swift
}

private func functionGlobalActorType(in attributes: String) -> Any.Type? {
    let candidates = attributes.split(separator: " ").filter {
        $0.hasPrefix("@")
            && $0 != "@Sendable"
            && $0 != "@escaping"
            && $0 != "@isolated(any)"
            && $0 != "@convention(c)"
            && $0 != "@convention(block)"
            && $0 != "nonisolated(nonsending)"
    }
    guard candidates.count == 1 else { return nil }
    return resolveRuntimeType(String(candidates[0].dropFirst()))
}

private struct ParsedTupleElement {
    let label: String?
    let typeName: String
}

private func parsedTupleElements(_ name: String) -> [ParsedTupleElement]? {
    guard name.first == "(", name.last == ")" else { return nil }
    let contents = String(name.dropFirst().dropLast())
    guard contents.isEmpty == false else { return [] }
    guard let components = topLevelComponents(in: contents) else { return nil }
    return components.map { element in
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

/// Resolves `[Element]` and `[Key: Value]` bracket sugar as printed by the
/// Swift demangler.
private func bracketCollectionType(_ name: String) -> Any.Type? {
    guard name.first == "[", name.last == "]" else { return nil }
    let contents = String(name.dropFirst().dropLast())
    guard contents.isEmpty == false else { return nil }
    if let colon = lastTopLevelColon(in: contents) {
        guard
            let key = resolveRuntimeType(
                String(contents[..<colon]).trimmingCharacters(in: .whitespaces)
            ),
            let value = resolveRuntimeType(
                String(contents[contents.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
            )
        else {
            return nil
        }
        return dictionaryType(key: key, value: value)
    }
    guard let element = resolveRuntimeType(contents) else { return nil }
    return _openExistential(element, do: arrayType)
}

func setType(of element: Any.Type) -> Any.Type? {
    guard let hashableElement = element as? any Hashable.Type else { return nil }
    return openedSetType(of: hashableElement)
}

private func openedSetType<Element: Hashable>(of _: Element.Type) -> Any.Type {
    Set<Element>.self
}

func resultType(success: Any.Type, failure: Any.Type) -> Any.Type? {
    guard let errorType = failure as? any Error.Type else { return nil }
    return openedResultType(success: success, failure: errorType)
}

private func openedResultType<Failure: Error>(
    success: Any.Type,
    failure _: Failure.Type
) -> Any.Type {
    func openSuccess<Success>(_: Success.Type) -> Any.Type {
        Result<Success, Failure>.self
    }
    return _openExistential(success, do: openSuccess)
}

func dictionaryType(key: Any.Type, value: Any.Type) -> Any.Type? {
    guard let hashableKey = key as? any Hashable.Type else { return nil }
    return openedDictionaryType(key: hashableKey, value: value)
}

private func openedDictionaryType<Key: Hashable>(
    key _: Key.Type,
    value: Any.Type
) -> Any.Type {
    func openValue<Value>(_: Value.Type) -> Any.Type {
        Dictionary<Key, Value>.self
    }
    return _openExistential(value, do: openValue)
}

func optionalType<Wrapped>(of _: Wrapped.Type) -> Any.Type {
    Optional<Wrapped>.self
}

func arrayType<Element>(of _: Element.Type) -> Any.Type {
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
        if let type = swiftTypeByExportedMetadataSymbol(prefix + suffix) {
            return type
        }
    }
    return nil
}

/// Public noncopyable nominal types expose concrete metadata even though the
/// runtime's generic mangled-name lookup intentionally declines to instantiate
/// them. Swift's exported `N` symbol is the metadata object itself.
private func swiftTypeByExportedMetadataSymbol(_ mangledType: String) -> Any.Type? {
    let symbolName = "$s\(mangledType)N"
    guard let metadata = RuntimeSymbols.rawSymbol(named: symbolName) else { return nil }
    return unsafeBitCast(metadata, to: Any.Type.self)
}

private func swiftTypeByMangledName(_ name: String) -> Any.Type? {
    guard let swiftGetTypeByMangledNameInContext else {
        return nil
    }
    return name.utf8CString.withUnsafeBufferPointer { buffer -> Any.Type? in
        guard let base = buffer.baseAddress else { return nil }
        guard
            let metadata = swiftGetTypeByMangledNameInContext(
                UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
                UInt(name.utf8.count),
                nil,
                nil
            )
        else {
            return nil
        }
        return unsafeBitCast(metadata, to: Any.Type.self)
    }
}

private typealias SwiftGetTypeByMangledNameInContext =
    @convention(c) (
        UnsafePointer<UInt8>,
        UInt,
        UnsafeRawPointer?,
        UnsafeRawPointer?
    ) -> UnsafeRawPointer?

private var swiftGetTypeByMangledNameInContext: SwiftGetTypeByMangledNameInContext? {
    RuntimeSymbols.function(named: "swift_getTypeByMangledNameInContext")
}

private typealias SwiftGetFunctionTypeMetadata =
    @convention(c) (
        UInt,
        UnsafePointer<UnsafeRawPointer>?,
        UnsafePointer<UInt32>?,
        UnsafeRawPointer
    ) -> UnsafeRawPointer?

private var swiftGetFunctionTypeMetadata: SwiftGetFunctionTypeMetadata? {
    RuntimeSymbols.function(named: "swift_getFunctionTypeMetadata")
}

private typealias SwiftGetFunctionTypeMetadataGlobalActor =
    @convention(c) (
        UInt,
        UInt,
        UnsafePointer<UnsafeRawPointer>?,
        UnsafePointer<UInt32>?,
        UnsafeRawPointer,
        UnsafeRawPointer
    ) -> UnsafeRawPointer?

private var swiftGetFunctionTypeMetadataGlobalActor: SwiftGetFunctionTypeMetadataGlobalActor? {
    RuntimeSymbols.function(named: "swift_getFunctionTypeMetadataGlobalActor")
}

private typealias SwiftGetExtendedFunctionTypeMetadata =
    @convention(c) (
        UInt,
        UInt,
        UnsafePointer<UnsafeRawPointer>?,
        UnsafePointer<UInt32>?,
        UnsafeRawPointer,
        UnsafeRawPointer?,
        UInt32,
        UnsafeRawPointer?
    ) -> UnsafeRawPointer?

private var swiftGetExtendedFunctionTypeMetadata: SwiftGetExtendedFunctionTypeMetadata? {
    RuntimeSymbols.function(named: "swift_getExtendedFunctionTypeMetadata")
}
