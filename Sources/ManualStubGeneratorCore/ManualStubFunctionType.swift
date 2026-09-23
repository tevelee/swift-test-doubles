import Foundation

/// A parsed function type such as `@Sendable (Int, inout String) async throws -> Bool`.
struct FunctionTypeSyntax {
    let attributes: [String]
    let parameters: [String]
    let isAsync: Bool
    /// `throws`, `throws(Failure)`, or `nil`.
    let throwsClause: String?
    let result: String

    var isThrowing: Bool { throwsClause != nil }

    /// A global actor attribute, such as `@MainActor`, isolating the function.
    var globalActor: String? {
        attributes.first { $0 == "@MainActor" || ($0.hasSuffix("Actor") && $0 != "@Actor") }
    }

    init?(_ type: String) {
        var remainder = Substring(type.trimmingCharacters(in: .whitespaces))
        var attributes = [String]()
        while remainder.hasPrefix("@") {
            let end = remainder.firstIndex(where: { $0.isWhitespace || $0 == "(" }) ?? remainder.endIndex
            var attribute = String(remainder[..<end])
            remainder = remainder[end...]
            if remainder.hasPrefix("("), attribute == "@convention" || attribute == "@differentiable" {
                // Attribute arguments: this generator only forwards Swift closures.
                return nil
            }
            attribute = attribute.trimmingCharacters(in: .whitespaces)
            attributes.append(attribute)
            remainder = remainder.drop(while: \.isWhitespace)
        }
        for modifier in ["sending ", "borrowing ", "consuming "] where remainder.hasPrefix(modifier) {
            remainder = remainder.dropFirst(modifier.count).drop(while: \.isWhitespace)
        }
        let value = String(remainder)
        guard value.hasPrefix("("),
            let closing = functionTypeClosingParen(in: value),
            let arrow = value[closing...].range(of: "->")
        else { return nil }
        let effectText = value[value.index(after: closing) ..< arrow.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let result = value[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        guard result.isEmpty == false else { return nil }
        let inner = String(value[value.index(after: value.startIndex) ..< closing])
        let parameters: [String] =
            inner.trimmingCharacters(in: .whitespaces).isEmpty
            ? []
            : splitTopLevel(inner, on: ",").map { parameter in
                let trimmed = parameter.trimmingCharacters(in: .whitespaces)
                // Drop an `_ name:` label, which function types allow.
                if let colon = topLevelColon(in: trimmed) {
                    return trimmed[trimmed.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
        self.attributes = attributes
        self.parameters = parameters
        isAsync = effectText.contains("async")
        if let range = effectText.range(of: "throws") {
            throwsClause = String(effectText[range.lowerBound...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            throwsClause = nil
        }
        self.result = result
    }
}

private func functionTypeClosingParen(in value: String) -> String.Index? {
    var depth = 0
    for index in value.indices {
        if value[index] == "(" { depth += 1 }
        if value[index] == ")" {
            depth -= 1
            if depth == 0 { return index }
        }
    }
    return nil
}

private func topLevelColon(in value: String) -> String.Index? {
    var depth = 0
    for index in value.indices {
        switch value[index] {
            case "(", "[", "<": depth += 1
            case ")", "]", ">": depth -= 1
            case ":" where depth == 0: return index
            default: break
        }
    }
    return nil
}
