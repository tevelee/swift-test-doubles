import Foundation

/// A SIL-level function spelling emitted for reabstraction thunks. Lowered
/// ownership and result conventions are deliberately kept distinct from
/// source-level function syntax because their attributes are not interchangeable.
struct LoweredFunctionSyntax: Equatable {
    let canonicalSpelling: String
    let prefix: String
    let parameters: [LoweredFunctionParameterSyntax]
    let result: LoweredTypeSyntax
    let thrownError: LoweredTypeSyntax?

    init?(_ spelling: String) {
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
        guard rawResult.first == "(",
            let rawResultScanner = DelimitedSyntaxScanner(rawResult),
            let resultClosing = rawResultScanner.matchingClosingDelimiter(
                openingAt: rawResult.startIndex
            )
        else {
            return nil
        }
        let substitution = rawResult[rawResult.index(after: resultClosing)...]
            .trimmingCharacters(in: .whitespaces)
        guard
            substitution.isEmpty
                || (substitution.hasPrefix("for <") && substitution.last == ">")
        else {
            return nil
        }
        let resultContents = String(
            rawResult[rawResult.index(after: rawResult.startIndex) ..< resultClosing]
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
    }

    var isEscaping: Bool { prefix.contains("@escaping") }
    var isSendable: Bool { prefix.contains("@Sendable") }
    var isIsolated: Bool { prefix.contains("@isolated(any)") }
    var isAsync: Bool { prefix.contains("@async") }
    var isThrowing: Bool { thrownError != nil }
    var isGeneric: Bool {
        canonicalSpelling.contains("@in_guaranteed")
            || canonicalSpelling.contains("@out ")
    }

    var globalActor: DemangledTypeSyntax? {
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

struct LoweredFunctionParameterSyntax: Equatable {
    let canonicalSpelling: String
    let type: LoweredTypeSyntax
    let ownership: UInt32
    let isIsolated: Bool

    init?(_ spelling: String) {
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
        self.isIsolated =
            attributes.contains("isolated")
            || attributes.contains("@sil_isolated")
    }
}

indirect enum LoweredTypeSyntax: Equatable {
    case source(DemangledTypeSyntax)
    case function(LoweredFunctionSyntax)
    case implicitActor
    case substituted(String)

    init?(_ component: String) {
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
