import Foundation

/// A SIL-level function spelling emitted for reabstraction thunks. Lowered
/// ownership and result conventions are deliberately kept distinct from
/// source-level function syntax because their attributes are not interchangeable.
package struct LoweredFunctionSyntax: Equatable {
    package let canonicalSpelling: String
    package let prefix: String
    package let parameters: [LoweredFunctionParameterSyntax]
    package let result: LoweredTypeSyntax
    package let thrownError: LoweredTypeSyntax?

    package init?(_ spelling: String) {
        let canonicalSpelling = spelling.trimmingCharacters(in: .whitespaces)
        guard let scanner = DelimitedSyntaxScanner(canonicalSpelling),
            let callee = canonicalSpelling.range(of: "@callee"),
            let opening = canonicalSpelling[callee.upperBound...].firstIndex(of: "("),
            let closing = scanner.matchingClosingDelimiter(openingAt: opening),
            let arrow = scanner.topLevelRange(of: "->"),
            closing < arrow.lowerBound,
            canonicalSpelling[
                canonicalSpelling.index(after: closing) ..< arrow.lowerBound
            ].trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return nil
        }

        let parameterText = String(
            canonicalSpelling[
                canonicalSpelling.index(after: opening) ..< closing
            ]
        )
        let parameterComponents: [String]
        if parameterText.isEmpty {
            parameterComponents = []
        } else {
            guard let parameterScanner = DelimitedSyntaxScanner(parameterText)
            else {
                return nil
            }
            parameterComponents = parameterScanner.components(
                separatedBy: ",",
                omittingEmptySubsequences: true
            )
        }
        let parameters = parameterComponents.compactMap(
            LoweredFunctionParameterSyntax.init
        )
        guard parameters.count == parameterComponents.count else { return nil }

        let rawResult = canonicalSpelling[arrow.upperBound...]
            .trimmingCharacters(in: .whitespaces)
        let resultPrefix = "sending "
        let hasSendingResult = rawResult.hasPrefix(resultPrefix)
        let resultSpelling =
            hasSendingResult
            ? rawResult.dropFirst(resultPrefix.count)
                .trimmingCharacters(in: .whitespaces)
            : rawResult
        guard resultSpelling.first == "(",
            let rawResultScanner = DelimitedSyntaxScanner(resultSpelling),
            let resultClosing = rawResultScanner.matchingClosingDelimiter(
                openingAt: resultSpelling.startIndex
            )
        else {
            return nil
        }
        let substitution = resultSpelling[
            resultSpelling.index(after: resultClosing)...
        ]
        .trimmingCharacters(in: .whitespaces)
        guard
            substitution.isEmpty
                || (substitution.hasPrefix("for <") && substitution.last == ">")
        else {
            return nil
        }
        let resultContents = String(
            resultSpelling[
                resultSpelling.index(after: resultSpelling.startIndex)
                    ..< resultClosing
            ]
        )
        guard let resultScanner = DelimitedSyntaxScanner(resultContents) else {
            return nil
        }
        let resultComponents =
            resultContents.isEmpty
            ? []
            : resultScanner.components(
                separatedBy: ",",
                omittingEmptySubsequences: true
            )
        let errorComponents = resultComponents.filter(
            LoweredTypeSyntax.hasErrorConvention
        )
        guard errorComponents.count <= 1 else { return nil }
        let thrownError = errorComponents.first.flatMap(LoweredTypeSyntax.init)
        guard thrownError != nil || errorComponents.isEmpty else { return nil }

        let valueComponents = resultComponents.filter {
            LoweredTypeSyntax.hasErrorConvention($0) == false
        }
        guard valueComponents.count <= 1 else { return nil }
        let result: LoweredTypeSyntax
        if let value = valueComponents.first {
            guard let parsed = LoweredTypeSyntax(value) else { return nil }
            result = parsed
        } else {
            result = .source(.concrete("Swift.Void"))
        }

        self.canonicalSpelling = canonicalSpelling
        self.prefix = canonicalSpelling[..<opening]
            .trimmingCharacters(in: .whitespaces)
        self.parameters = parameters
        self.result = result
        self.thrownError = thrownError
        self.hasSendingResult = hasSendingResult
    }

    package var isEscaping: Bool { prefix.contains("@escaping") }
    package var isSendable: Bool { prefix.contains("@Sendable") }
    package var isIsolated: Bool { prefix.contains("@isolated(any)") }
    package var isAsync: Bool { prefix.contains("@async") }
    package var isThrowing: Bool { thrownError != nil }
    package let hasSendingResult: Bool
    package var isGeneric: Bool {
        canonicalSpelling.contains("@in_guaranteed")
            || canonicalSpelling.contains("@out ")
    }

    package var globalActor: DemangledTypeSyntax? {
        let knownAttributes = [
            "@async", "@callee_guaranteed", "@callee_owned", "@callee_unowned",
            "@convention(thin)", "@escaping", "@isolated(any)", "@noescape",
            "@Sendable"
        ]
        for word in prefix.split(separator: " ")
        where word.hasPrefix("@") && knownAttributes.contains(String(word)) == false {
            if let syntax = DemangledTypeSyntax(String(word.dropFirst())),
                resolveRuntimeType(syntax) != nil
            {
                return syntax
            }
        }
        return nil
    }
}

package struct LoweredFunctionParameterSyntax: Equatable {
    package let canonicalSpelling: String
    package let type: LoweredTypeSyntax
    package let ownership: UInt32
    package let isIsolated: Bool
    package let isSending: Bool

    package init?(_ spelling: String) {
        let canonicalSpelling = spelling.trimmingCharacters(in: .whitespaces)
        let attributes = canonicalSpelling.split(separator: " ")
        let ownership: UInt32
        if attributes.contains("@inout") {
            ownership = 1
        } else if attributes.contains("@owned") || attributes.contains("@in") {
            ownership = 3
        } else {
            ownership = 0
        }
        guard let type = LoweredTypeSyntax(canonicalSpelling) else { return nil }
        self.canonicalSpelling = canonicalSpelling
        self.type = type
        self.ownership = ownership
        // "@sil_isolated" is the separate SIL-textual-printer spelling
        // (docs/SIL/Types.md); swift_demangle's NodePrinter.cpp only ever
        // emits the bare "isolated" keyword this checks alongside.
        self.isIsolated = attributes.contains("isolated")
        self.isSending = attributes.contains("sending")
    }
}

package indirect enum LoweredTypeSyntax: Equatable {
    case source(DemangledTypeSyntax)
    case function(LoweredFunctionSyntax)
    case implicitActor
    case substituted(String)

    package init?(_ component: String) {
        let canonicalSpelling = component.trimmingCharacters(in: .whitespaces)
        guard canonicalSpelling.isEmpty == false,
            DelimitedSyntaxScanner(canonicalSpelling) != nil
        else {
            return nil
        }
        if canonicalSpelling.range(of: "@callee") != nil {
            guard let function = LoweredFunctionSyntax(canonicalSpelling) else {
                return nil
            }
            self = .function(function)
            return
        }

        var words = canonicalSpelling.split(separator: " ").map(String.init)
        let isSubstituted = words.contains(where: { $0 == "@substituted" })
        while words.first?.hasPrefix("@") == true {
            words.removeFirst()
        }
        if words.first == "isolated" {
            words.removeFirst()
        }
        if words.first == "sending" {
            words.removeFirst()
        }
        let spelling = words.joined(separator: " ")
        guard spelling.isEmpty == false else { return nil }
        if spelling == "Builtin.ImplicitActor" {
            self = .implicitActor
        } else if isSubstituted || spelling.hasPrefix("τ_") {
            self = .substituted(canonicalSpelling)
        } else if let source = DemangledTypeSyntax(spelling) {
            self = .source(source)
        } else {
            return nil
        }
    }

    fileprivate static func hasErrorConvention(_ component: String) -> Bool {
        let value = component.trimmingCharacters(in: .whitespaces)
        if let callee = value.range(of: "@callee") {
            return value[..<callee.lowerBound]
                .split(separator: " ").contains("@error")
        }
        return value.split(separator: " ").first == "@error"
    }
}
