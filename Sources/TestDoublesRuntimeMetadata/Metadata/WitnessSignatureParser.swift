import Echo
import Foundation

// MARK: - Signature parsing

package struct ParsedWitnessSignature {
    package let name: String
    package let argumentTypes: [DemangledTypeSyntax]
    package let argumentIsVariadic: [Bool]
    package let argumentIsAutoclosure: [Bool]
    package let returnType: DemangledTypeSyntax
    package let isThrowing: Bool
    package let typedError: DemangledTypeSyntax?

    package var argumentTypeNames: [String] {
        argumentTypes.map(\.canonicalSpelling)
    }

    package var returnTypeName: String {
        returnType.canonicalSpelling
    }

    package var typedErrorName: String? {
        typedError?.canonicalSpelling
    }
}

package func parseWitnessSignature(
    _ demangled: String,
    kind: ProtocolRequirement.Kind
) -> ParsedWitnessSignature? {
    // Strip the runtime symbol wrapper and any conformance suffix.
    let stripped: String
    if let range = demangled.range(of: " in conformance") {
        stripped = String(demangled[..<range.lowerBound])
    } else {
        stripped = demangled
    }

    let prefixes = [
        "coro function pointer to ",
        "protocol witness for ",
        "method descriptor for ",
        "dispatch thunk of "
    ]
    let unwrapped = prefixes.reduce(stripped) { result, prefix in
        result.hasPrefix(prefix) ? String(result.dropFirst(prefix.count)) : result
    }
    let cleaned = strippingLocalDeclarationContext(unwrapped)

    // Accessor: "count.getter : Int", "count.setter : Int", or
    // "subscript.getter : (Swift.Int) -> Swift.String".
    if kind == .getter || kind == .setter || kind == .readCoroutine {
        let markers: [String]
        switch kind {
            case .getter:
                markers = [".getter : "]
            case .setter:
                markers = [".setter : "]
            case .readCoroutine:
                // The live Swift 6.3.3 toolchain demangles a yield_once_2
                // read witness as ".read2 : "; swiftlang/swift@main's
                // NodePrinter.cpp no longer has a distinct node for it (it
                // prints "read" for both the legacy and yield_once_2 forms),
                // so treat ".read2 : " as a version-specific spelling rather
                // than dropping it. ".borrow : " covers the newer
                // BorrowAccessor node kind main does have.
                markers = [".yielding_borrow : ", ".read2 : ", ".borrow : ", ".read : "]
            default:
                preconditionFailure("Accessor kind was validated before parsing.")
        }
        for marker in markers {
            if let range = cleaned.range(of: marker) {
                return parseAccessorSignature(cleaned, accessorTypeAt: range, kind: kind)
            }
        }
    }

    // Method: "fetch(id: Swift.Int) -> Swift.String"
    // Also handles: "fetch(id: Swift.Int) throws -> Swift.String"
    if let scanner = DelimitedSyntaxScanner(cleaned),
        let arrow = scanner.topLevelRange(of: "->"),
        let (parenOpen, closeParen) = lastParameterList(
            in: scanner,
            before: arrow.lowerBound
        ),
        let parameters = parseParameters(
            String(cleaned[cleaned.index(after: parenOpen) ..< closeParen])
        ),
        let effects = DemangledFunctionEffectSyntax(
            String(cleaned[cleaned.index(after: closeParen) ..< arrow.lowerBound])
        ),
        let returnType = DemangledTypeSyntax(String(cleaned[arrow.upperBound...]))
    {
        let methodName = extractMethodName(String(cleaned[..<parenOpen]))
        return ParsedWitnessSignature(
            name: buildMethodName(methodName, parameters: parameters),
            argumentTypes: parameters.map(\.type),
            argumentIsVariadic: parameters.map(\.isVariadic),
            argumentIsAutoclosure: parameters.map(\.isAutoclosure),
            returnType: returnType,
            isThrowing: effects.isThrowing,
            typedError: effects.thrownError
        )
    }

    return nil
}

/// Strips the trailing declaration context of a requirement declared inside a
/// function, method, or closure, which prints as
/// `read(path: Swift.String) -> Foundation.Data in P #1 in test2.f() -> ()`
/// instead of qualifying the name. Only a local declaration prints the
/// `Name #<discriminator> in ` head, so the first top-level occurrence marks
/// where the signature ends.
private func strippingLocalDeclarationContext(_ text: String) -> String {
    guard let scanner = DelimitedSyntaxScanner(text) else { return text }
    var searchStart = text.startIndex
    while searchStart < text.endIndex,
        let range = text.range(of: " in ", range: searchStart ..< text.endIndex)
    {
        if scanner.isTopLevel(range.lowerBound),
            startsWithLocalDeclarationContext(text[range.upperBound...])
        {
            return String(text[..<range.lowerBound])
        }
        searchStart = range.upperBound
    }
    return text
}

private func startsWithLocalDeclarationContext(_ text: Substring) -> Bool {
    func isNameCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
    guard let first = text.first, first == "_" || first.isLetter else {
        return false
    }
    var rest = text.drop(while: isNameCharacter)
    guard rest.hasPrefix(" #") else { return false }
    rest = rest.dropFirst(2)
    let discriminator = rest.prefix(while: \.isNumber)
    guard discriminator.isEmpty == false else { return false }
    return rest.dropFirst(discriminator.count).hasPrefix(" in ")
}

/// Parses a property or subscript accessor signature. Swift subscript setters
/// pass the owned new value before their borrowed indices; the implicit Self
/// parameter is carried separately by the witness calling convention.
private func parseAccessorSignature(
    _ cleaned: String,
    accessorTypeAt markerRange: Range<String.Index>,
    kind: ProtocolRequirement.Kind
) -> ParsedWitnessSignature? {
    guard
        let propertyName = String(cleaned[..<markerRange.lowerBound])
            .components(separatedBy: ".").last,
        propertyName.isEmpty == false
    else {
        return nil
    }
    let accessorType = String(cleaned[markerRange.upperBound...])
    let valueType: DemangledTypeSyntax
    let indexTypes: [DemangledTypeSyntax]
    if propertyName == "subscript" {
        guard let signature = parseSubscriptAccessorType(accessorType) else {
            return nil
        }
        (indexTypes, valueType) = signature
    } else {
        guard let parsedValueType = DemangledTypeSyntax(accessorType) else {
            return nil
        }
        valueType = parsedValueType
        indexTypes = []
    }
    return ParsedWitnessSignature(
        name: propertyName,
        argumentTypes: kind == .setter
            ? [valueType] + indexTypes
            : indexTypes,
        argumentIsVariadic: Array(
            repeating: false,
            count: (kind == .setter ? 1 : 0) + indexTypes.count
        ),
        argumentIsAutoclosure: Array(
            repeating: false,
            count: (kind == .setter ? 1 : 0) + indexTypes.count
        ),
        returnType: kind == .setter
            ? .concrete("Swift.Void")
            : valueType,
        isThrowing: false,
        typedError: nil
    )
}

private func parseSubscriptAccessorType(
    _ accessorType: String
) -> (indexTypes: [DemangledTypeSyntax], valueType: DemangledTypeSyntax)? {
    let accessorType = accessorType.trimmingCharacters(in: .whitespaces)
    guard accessorType.first == "(" else {
        return nil
    }
    let opening = accessorType.startIndex
    guard let scanner = DelimitedSyntaxScanner(accessorType),
        let closing = scanner.matchingClosingDelimiter(openingAt: opening)
    else {
        return nil
    }
    let suffix = accessorType[accessorType.index(after: closing)...]
    guard suffix.hasPrefix(" -> ") else { return nil }
    let resultStart = suffix.index(suffix.startIndex, offsetBy: 4)
    let parameters = accessorType[accessorType.index(after: opening) ..< closing]
    guard let parsedParameters = parseParameters(String(parameters)),
        let valueType = DemangledTypeSyntax(String(suffix[resultStart...]))
    else {
        return nil
    }
    return (
        parsedParameters.map(\.type),
        valueType
    )
}

private struct ParsedParameter {
    let label: String
    let type: DemangledTypeSyntax
    let isVariadic: Bool
    let isAutoclosure: Bool
}

private func parseParameters(_ text: String) -> [ParsedParameter]? {
    guard !text.isEmpty else { return [] }
    guard let components = topLevelComponents(in: text) else { return nil }
    var parameters: [ParsedParameter] = []
    for parameter in components {
        guard let colon = lastTopLevelColon(in: parameter) else {
            guard let parsed = parameterType(parameter) else { return nil }
            parameters.append(
                ParsedParameter(
                    label: "_",
                    type: parsed.type,
                    isVariadic: parsed.isVariadic,
                    isAutoclosure: parsed.isAutoclosure
                )
            )
            continue
        }
        let label = parameter[..<colon].trimmingCharacters(in: .whitespaces)
        guard
            let parsed = parameterType(
                String(parameter[parameter.index(after: colon)...])
            )
        else {
            return nil
        }
        parameters.append(
            ParsedParameter(
                label: label,
                type: parsed.type,
                isVariadic: parsed.isVariadic,
                isAutoclosure: parsed.isAutoclosure
            )
        )
    }
    return parameters
}

/// Swift's demangler preserves source-level `...` spelling in a witness
/// symbol, while the witness ABI receives one `Array<Element>` parameter.
/// Normalize it before metadata resolution so the decoded runtime argument,
/// typed handler, and matcher list all agree on the single collection value.
private func parameterType(
    _ spelling: String
) -> (
    type: DemangledTypeSyntax,
    isVariadic: Bool,
    isAutoclosure: Bool
)? {
    let spelling = spelling.trimmingCharacters(in: .whitespaces)
    let isVariadic = spelling.hasSuffix("...")
    let elementSpelling =
        isVariadic
        ? String(spelling.dropLast(3)).trimmingCharacters(in: .whitespaces)
        : spelling
    let isAutoclosure = elementSpelling.hasPrefix("@autoclosure ")
    guard let type = DemangledTypeSyntax(elementSpelling) else { return nil }
    guard isVariadic else { return (type, false, isAutoclosure) }
    guard let array = DemangledTypeSyntax("Swift.Array<\(type.canonicalSpelling)>")
    else {
        return nil
    }
    return (array, true, isAutoclosure)
}

private func buildMethodName(_ baseName: String, parameters: [ParsedParameter]) -> String {
    guard parameters.isEmpty == false else { return "\(baseName)()" }
    let labels = parameters.map { $0.label == "_" ? "_:" : "\($0.label):" }
    return "\(baseName)(\(labels.joined()))"
}

/// Extracts the base name from a qualified declaration path such as
/// `"Module.P.fetch"` or, for a generic protocol requirement, `"Module.P.fetch<A>"`.
/// Splitting is top-level-aware so neither a dot inside a generic argument
/// clause (`"Module.P.take<Swift.Int>"`) nor the clause itself ends up in the
/// extracted name.
private func extractMethodName(_ str: String) -> String {
    guard let scanner = DelimitedSyntaxScanner(str) else {
        return str.components(separatedBy: ".").last ?? str
    }
    let nameStart = scanner.lastTopLevelIndex(of: ".").map(str.index(after:)) ?? str.startIndex
    return strippingTrailingGenericParameterClause(from: String(str[nameStart...]))
}

private func strippingTrailingGenericParameterClause(from name: String) -> String {
    guard let openAngle = name.firstIndex(of: "<"),
        let scanner = DelimitedSyntaxScanner(name),
        scanner.isTopLevel(openAngle),
        scanner.matchingClosingDelimiter(openingAt: openAngle)
            == name.index(before: name.endIndex)
    else {
        return name
    }
    return String(name[..<openAngle])
}

private func lastParameterList(
    in scanner: DelimitedSyntaxScanner,
    before end: String.Index
) -> (opening: String.Index, closing: String.Index)? {
    let text = scanner.text
    var candidate: (opening: String.Index, closing: String.Index)?
    for pair in scanner.pairs(openedBy: "(") {
        let opening = pair.opening
        let closing = pair.closing
        let prefix = text[..<opening].trimmingCharacters(in: .whitespaces)
        guard opening < end,
            prefix.hasSuffix("throws") == false,
            closing < end
        else {
            continue
        }
        if candidate == nil || candidate!.closing < closing {
            candidate = (opening, closing)
        }
    }
    return candidate
}
