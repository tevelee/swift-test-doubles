import Foundation

/// A validated source-level type spelling emitted by Swift's demangler.
///
/// Only the function structure consumed by the runtime bridge is modeled;
/// other spellings stay canonical leaf nodes interpreted by runtime type
/// resolution, keeping syntax validation separate from metadata lookup.
package indirect enum DemangledTypeSyntax: Equatable {
    case concrete(String)
    case function(DemangledFunctionTypeSyntax)

    package init?(_ spelling: String) {
        let canonicalSpelling = spelling.trimmingCharacters(in: .whitespaces)
        guard canonicalSpelling.isEmpty == false,
            let scanner = DelimitedSyntaxScanner(canonicalSpelling)
        else {
            return nil
        }
        if scanner.topLevelRange(of: "->") != nil {
            guard
                let function = DemangledFunctionTypeSyntax(
                    canonicalSpelling,
                    scanner: scanner
                )
            else {
                return nil
            }
            self = .function(function)
        } else {
            self = .concrete(
                canonicalSpelling == "()" ? "Swift.Void" : canonicalSpelling
            )
        }
    }

    package var canonicalSpelling: String {
        switch self {
            case .concrete(let spelling): spelling
            case .function(let function): function.canonicalSpelling
        }
    }
}

package struct DemangledFunctionTypeSyntax: Equatable {
    package let canonicalSpelling: String
    package let attributes: String
    package let effects: DemangledFunctionEffectSyntax
    package let parameters: [DemangledFunctionParameterSyntax]
    package let result: DemangledTypeSyntax
    package let hasSendingResult: Bool

    fileprivate init?(
        _ canonicalSpelling: String,
        scanner: DelimitedSyntaxScanner
    ) {
        guard let arrow = scanner.topLevelRange(of: "->") else { return nil }
        for pair in scanner.pairs(openedBy: "(")
        where scanner.isTopLevel(pair.opening) && pair.closing < arrow.lowerBound {
            let attributes = canonicalSpelling[..<pair.opening]
                .trimmingCharacters(in: .whitespaces)
            guard Self.attributesHaveSupportedSyntax(attributes) else {
                continue
            }
            let rawEffects = canonicalSpelling[
                canonicalSpelling.index(after: pair.closing) ..< arrow.lowerBound
            ].trimmingCharacters(in: .whitespaces)
            guard let effects = DemangledFunctionEffectSyntax(rawEffects) else {
                continue
            }
            let parameterText = String(
                canonicalSpelling[
                    canonicalSpelling.index(after: pair.opening) ..< pair.closing
                ]
            )
            let parameterSpellings: [String]
            if parameterText.isEmpty {
                parameterSpellings = []
            } else {
                guard let parameterScanner = DelimitedSyntaxScanner(parameterText)
                else {
                    return nil
                }
                parameterSpellings = parameterScanner.components(separatedBy: ",")
            }
            let parameters = parameterSpellings.compactMap(
                DemangledFunctionParameterSyntax.init
            )
            guard parameters.count == parameterSpellings.count else { return nil }

            let rawResult = canonicalSpelling[arrow.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            let hasSendingResult = rawResult.hasPrefix("sending ")
            let resultSpelling =
                hasSendingResult
                ? String(rawResult.dropFirst("sending ".count))
                : rawResult
            guard let result = DemangledTypeSyntax(resultSpelling) else { return nil }

            self.canonicalSpelling = canonicalSpelling
            self.attributes = attributes
            self.effects = effects
            self.parameters = parameters
            self.result = result
            self.hasSendingResult = hasSendingResult
            return
        }
        return nil
    }

    private static func attributesHaveSupportedSyntax(_ attributes: String) -> Bool {
        attributes.split(separator: " ").allSatisfy {
            $0 == "@Sendable" || $0 == "@escaping" || $0 == "@isolated(any)"
                || $0 == "@convention(c)" || $0 == "@convention(block)"
                || $0 == "nonisolated(nonsending)"
                || ($0.hasPrefix("@") && $0.count > 1)
        }
    }
}

package struct DemangledFunctionEffectSyntax: Equatable {
    package let canonicalSpelling: String
    package let isAsync: Bool
    package let isThrowing: Bool
    package let thrownError: DemangledTypeSyntax?

    package init?(_ spelling: String) {
        let canonicalSpelling = spelling.trimmingCharacters(in: .whitespaces)
        guard let scanner = DelimitedSyntaxScanner(canonicalSpelling) else {
            return nil
        }

        let prefix: String
        let thrownError: DemangledTypeSyntax?
        if let marker = scanner.topLevelRange(of: "throws(") {
            let opening = canonicalSpelling.index(before: marker.upperBound)
            guard let closing = scanner.matchingClosingDelimiter(openingAt: opening),
                canonicalSpelling[canonicalSpelling.index(after: closing)...]
                    .trimmingCharacters(in: .whitespaces).isEmpty
            else {
                return nil
            }
            prefix = canonicalSpelling[..<marker.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let errorSpelling = String(
                canonicalSpelling[
                    canonicalSpelling.index(after: opening) ..< closing
                ]
            )
            guard let error = DemangledTypeSyntax(errorSpelling) else { return nil }
            thrownError = error
        } else {
            prefix = canonicalSpelling
            thrownError = nil
        }

        let words = prefix.split(separator: " ")
        guard words.allSatisfy({ $0 == "async" || $0 == "throws" }) else {
            return nil
        }
        self.canonicalSpelling = canonicalSpelling
        self.isAsync = words.contains("async")
        self.isThrowing = thrownError != nil || words.contains("throws")
        self.thrownError = thrownError
    }
}

package struct DemangledFunctionParameterSyntax: Equatable {
    package enum Ownership: UInt32, Equatable {
        case `default` = 0
        case inoutValue = 1
        case borrowed = 2
        case owned = 3
    }

    package let canonicalSpelling: String
    package let type: DemangledTypeSyntax
    package let ownership: Ownership
    package let isIsolated: Bool
    package let isSending: Bool
    package let isAutoclosure: Bool
    package let isVariadic: Bool

    package init?(_ spelling: String) {
        let canonicalSpelling = spelling.trimmingCharacters(in: .whitespaces)
        var value = canonicalSpelling

        let isIsolated = value.hasPrefix("isolated ")
        if isIsolated { value.removeFirst("isolated ".count) }
        let isSending = value.hasPrefix("sending ")
        if isSending { value.removeFirst("sending ".count) }

        // NodePrinter.cpp never prints the source-level "borrowing"/"consuming"
        // keywords; SE-0377 parameters demangle as the SIL-level "__shared"/
        // "__owned" conventions instead.
        let ownershipPrefixes: [(String, Ownership)] = [
            ("inout ", .inoutValue),
            ("__shared ", .borrowed),
            ("__owned ", .owned)
        ]
        var ownership = Ownership.default
        for (prefix, candidate) in ownershipPrefixes where value.hasPrefix(prefix) {
            ownership = candidate
            value.removeFirst(prefix.count)
            break
        }

        let isAutoclosure = value.hasPrefix("@autoclosure ")
        if isAutoclosure { value.removeFirst("@autoclosure ".count) }
        let isVariadic = value.hasSuffix("...")
        if isVariadic { value.removeLast(3) }
        guard let type = DemangledTypeSyntax(value) else { return nil }

        self.canonicalSpelling = canonicalSpelling
        self.type = type
        self.ownership = ownership
        self.isIsolated = isIsolated
        self.isSending = isSending
        self.isAutoclosure = isAutoclosure
        self.isVariadic = isVariadic
    }
}
