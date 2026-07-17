import Foundation

/// Delimiter-aware navigation for Swift's demangled type and lowered function
/// spellings. The scanner validates the complete input before exposing ranges,
/// so callers fail closed on mismatched or unterminated syntax.
struct DelimitedSyntaxScanner {
    struct DelimiterPair {
        let opening: String.Index
        let closing: String.Index
    }

    private enum Delimiter: Character {
        case parenthesis = "("
        case angle = "<"
        case bracket = "["

        var closing: Character {
            switch self {
                case .parenthesis: ")"
                case .angle: ">"
                case .bracket: "]"
            }
        }
    }

    let text: String

    private let depthBeforeIndex: [String.Index: Int]
    private let delimiterPairs: [Delimiter: [DelimiterPair]]
    private let matchingClosingIndices: [String.Index: String.Index]

    init?(_ text: String) {
        var depthBeforeIndex: [String.Index: Int] = [:]
        var delimiterPairs: [Delimiter: [DelimiterPair]] = [:]
        var matchingClosingIndices: [String.Index: String.Index] = [:]
        var stack: [(delimiter: Delimiter, opening: String.Index)] = []

        for index in text.indices {
            depthBeforeIndex[index] = stack.count
            let character = text[index]
            if let delimiter = Delimiter(rawValue: character) {
                stack.append((delimiter, index))
                continue
            }
            if character == ">", Self.isFunctionArrowHead(in: text, at: index) {
                continue
            }
            guard let closingDelimiter = Self.delimiter(closedBy: character) else {
                continue
            }
            guard let opening = stack.popLast(), opening.delimiter == closingDelimiter else {
                return nil
            }
            let pair = DelimiterPair(opening: opening.opening, closing: index)
            delimiterPairs[closingDelimiter, default: []].append(pair)
            matchingClosingIndices[opening.opening] = index
        }
        guard stack.isEmpty else { return nil }

        self.text = text
        self.depthBeforeIndex = depthBeforeIndex
        self.delimiterPairs = delimiterPairs
        self.matchingClosingIndices = matchingClosingIndices
    }

    func isTopLevel(_ index: String.Index) -> Bool {
        depthBeforeIndex[index] == 0
    }

    func topLevelRange(of token: String) -> Range<String.Index>? {
        guard token.isEmpty == false else { return nil }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
            let range = text.range(
                of: token,
                range: searchStart ..< text.endIndex
            )
        {
            if isTopLevel(range.lowerBound) {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    func lastTopLevelIndex(of character: Character) -> String.Index? {
        text.indices.last { text[$0] == character && isTopLevel($0) }
    }

    func components(
        separatedBy separator: Character,
        omittingEmptySubsequences: Bool = false
    ) -> [String] {
        var result: [String] = []
        var componentStart = text.startIndex
        for index in text.indices
        where text[index] == separator && isTopLevel(index) {
            appendComponent(
                text[componentStart ..< index],
                omittingEmptySubsequences: omittingEmptySubsequences,
                to: &result
            )
            componentStart = text.index(after: index)
        }
        appendComponent(
            text[componentStart...],
            omittingEmptySubsequences: omittingEmptySubsequences,
            to: &result
        )
        return result
    }

    func matchingClosingDelimiter(
        openingAt opening: String.Index
    ) -> String.Index? {
        matchingClosingIndices[opening]
    }

    func pairs(openedBy character: Character) -> [DelimiterPair] {
        guard let delimiter = Delimiter(rawValue: character) else { return [] }
        return delimiterPairs[delimiter, default: []].sorted {
            $0.opening < $1.opening
        }
    }

    private func appendComponent(
        _ component: Substring,
        omittingEmptySubsequences: Bool,
        to result: inout [String]
    ) {
        let value = component.trimmingCharacters(in: .whitespaces)
        if value.isEmpty == false || omittingEmptySubsequences == false {
            result.append(value)
        }
    }

    private static func delimiter(closedBy character: Character) -> Delimiter? {
        [Delimiter.parenthesis, .angle, .bracket].first {
            $0.closing == character
        }
    }

    private static func isFunctionArrowHead(
        in text: String,
        at index: String.Index
    ) -> Bool {
        guard index > text.startIndex else { return false }
        return text[text.index(before: index)] == "-"
    }
}
