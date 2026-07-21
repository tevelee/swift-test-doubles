import Echo
import Foundation

// MARK: - Signature parsing

struct ParsedWitnessSignature {
    let name: String
    let argumentTypes: [DemangledTypeSyntax]
    let returnType: DemangledTypeSyntax
    let isThrowing: Bool
    let typedError: DemangledTypeSyntax?

    var argumentTypeNames: [String] {
        argumentTypes.map(\.canonicalSpelling)
    }

    var returnTypeName: String {
        returnType.canonicalSpelling
    }

    var typedErrorName: String? {
        typedError?.canonicalSpelling
    }
}

func parseWitnessSignature(
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
    let cleaned = prefixes.reduce(stripped) { result, prefix in
        result.hasPrefix(prefix) ? String(result.dropFirst(prefix.count)) : result
    }

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
                markers = [".read2 : ", ".read : "]
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
            returnType: returnType,
            isThrowing: effects.isThrowing,
            typedError: effects.thrownError
        )
    }

    return nil
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
}

private func parseParameters(_ text: String) -> [ParsedParameter]? {
    guard !text.isEmpty else { return [] }
    guard let components = topLevelComponents(in: text) else { return nil }
    var parameters: [ParsedParameter] = []
    for parameter in components {
        guard let colon = lastTopLevelColon(in: parameter) else {
            guard let type = DemangledTypeSyntax(parameter) else { return nil }
            parameters.append(ParsedParameter(label: "_", type: type))
            continue
        }
        let label = parameter[..<colon].trimmingCharacters(in: .whitespaces)
        guard
            let type = DemangledTypeSyntax(
                String(parameter[parameter.index(after: colon)...])
            )
        else {
            return nil
        }
        parameters.append(ParsedParameter(label: label, type: type))
    }
    return parameters
}

private func buildMethodName(_ baseName: String, parameters: [ParsedParameter]) -> String {
    guard parameters.isEmpty == false else { return "\(baseName)()" }
    let labels = parameters.map { $0.label == "_" ? "_:" : "\($0.label):" }
    return "\(baseName)(\(labels.joined()))"
}

private func extractMethodName(_ str: String) -> String {
    str.components(separatedBy: ".").last ?? str
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

func topLevelComponents(in text: String) -> [String]? {
    DelimitedSyntaxScanner(text)?.components(separatedBy: ",")
}

func lastTopLevelColon(in text: String) -> String.Index? {
    DelimitedSyntaxScanner(text)?.lastTopLevelIndex(of: ":")
}
