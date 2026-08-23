import Foundation

package struct ManualStubGenerator {
    package let protocolName: String
    package let source: String

    package init(protocolName: String, source: String) {
        self.protocolName = protocolName
        self.source = source
    }

    package func render(
        importingTestDoubles: Bool = true,
        preservingSourceImports: Bool = true
    ) throws -> String {
        let declaration = try protocolDeclaration()
        let requirements = declaration.body.requirements
        let conformerName = "\(protocolName)StubConformer"
        let stubName = "\(protocolName)Stub"
        let conformerKind = declaration.inheritsActor ? "actor" : "struct"
        var members = [
            declaration.inheritsActor
                ? "let stub: ManualStub<\(conformerName)>\n\n    init(stub: ManualStub<\(conformerName)>) { self.stub = stub }"
                : "let stub: ManualStub<Self>"
        ]
        for requirement in requirements {
            try requireInstanceRequirement(requirement)
            if let member = try forwarder(for: requirement) {
                members.append(member)
            }
        }
        var imports = preservingSourceImports ? sourceImportLines() : []
        if importingTestDoubles, imports.contains("import TestDoubles") == false {
            imports.append("import TestDoubles")
        }
        let importBlock = imports.isEmpty ? "" : imports.joined(separator: "\n") + "\n\n"
        return """
            \(importBlock)\(conformerKind) \(conformerName): \(protocolName), ManualStubConformer {
                \(members.joined(separator: "\n\n    "))
            }

            typealias \(stubName) = ManualStub<\(conformerName)>

            extension ManualStub where T == \(conformerName) {
                /// Tries runtime synthesis, then uses this compiled conformer when needed.
                static func automatic() -> Stub<any \(protocolName)> {
                    Stub(
                        fallingBackTo: \(conformerName).self,
                        erasingWith: {
                            $0
                        }
                    )
                }
            }
            """ + "\n"
    }

    private func sourceImportLines() -> [String] {
        var seen: Set<String> = []
        return source.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard
                trimmed.hasPrefix("import ")
                    || trimmed.hasPrefix("@testable import ")
                    || trimmed.hasPrefix("@preconcurrency import ")
                    || trimmed.hasPrefix("@_exported import ")
            else {
                return nil
            }
            guard seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private func protocolDeclaration() throws -> SwiftProtocolDeclaration {
        guard
            let declaration = SwiftProtocolDeclarationScanner(source: source)
                .declarations()
                .first(where: { $0.name == protocolName })
        else {
            throw ManualStubGeneratorError.protocolNotFound(protocolName)
        }
        return declaration
    }

    private func forwarder(for requirement: String) throws -> String? {
        if requirement.contains(" func ") || requirement.hasPrefix("func ")
            || requirement.hasPrefix("static func ")
            || requirement.hasPrefix("class func ")
        {
            guard let result = functionForwarder(requirement) else {
                throw unsupported(requirement, because: "the function declaration could not be parsed")
            }
            return result
        }
        if requirement.contains(" var ") || requirement.hasPrefix("var ")
            || requirement.hasPrefix("static var ")
            || requirement.hasPrefix("class var ")
        {
            guard let result = propertyForwarder(requirement) else {
                throw unsupported(requirement, because: "the property declaration could not be parsed")
            }
            return result
        }
        if requirement.contains("subscript") {
            guard let result = subscriptForwarder(requirement) else {
                throw unsupported(requirement, because: "the subscript declaration could not be parsed")
            }
            return result
        }
        return nil
    }

    private func requireInstanceRequirement(_ requirement: String) throws {
        let declarationKind =
            requirement.range(of: "func ").map { requirement[..<$0.lowerBound] }
            ?? requirement.range(of: "var ").map { requirement[..<$0.lowerBound] }
            ?? requirement.range(of: "subscript").map { requirement[..<$0.lowerBound] }
        let modifiers = declarationKind.map(String.init) ?? requirement
        let modifierWords = modifiers.split(whereSeparator: \.isWhitespace)
        if modifierWords.contains("static") || modifierWords.contains("class") {
            throw unsupported(
                requirement,
                because:
                    "static requirements need shared process state and are unsafe in parallel tests"
            )
        }
        if declarationKind == nil,
            requirement.range(of: "init") != nil
        {
            throw unsupported(
                requirement,
                because:
                    "initializer requirements need shared process state and are unsafe in parallel tests"
            )
        }
    }

    private func unsupported(
        _ requirement: String,
        because reason: String
    ) -> ManualStubGeneratorError {
        .unsupportedRequirement(requirement: requirement, reason: reason)
    }

    private func functionForwarder(_ requirement: String) -> String? {
        guard let funcRange = requirement.range(of: "func ") else { return nil }
        let receiver = "stub"
        guard let opening = requirement[funcRange.upperBound...].firstIndex(of: "(") else {
            return nil
        }
        guard let closing = matchingParen(in: requirement, opening: opening) else {
            return nil
        }
        let arguments = invocationArguments(String(requirement[opening ... closing]))
        let suffix = String(requirement[closing...])
        let effects = effects(in: suffix)
        return "\(requirement) { \(forwardingInvocation(receiver: receiver, arguments: arguments, effects: effects)) }"
    }

    private func propertyForwarder(_ requirement: String) -> String? {
        let receiver = "stub"
        let bodyless =
            requirement.components(separatedBy: "{").first?.trimmingCharacters(
                in: .whitespaces
            ) ?? requirement
        guard let varRange = bodyless.range(of: "var "),
            let colon = bodyless[varRange.upperBound...].firstIndex(of: ":")
        else { return nil }
        let prefix = String(bodyless[..<varRange.lowerBound])
        let name = bodyless[varRange.upperBound ..< colon].trimmingCharacters(
            in: .whitespaces
        )
        let type = bodyless[bodyless.index(after: colon)...].trimmingCharacters(
            in: .whitespaces
        )
        guard requirement.contains("get") else { return nil }
        let getterEffects = effects(in: accessorSuffix(requirement, accessor: "get"))
        let getter = forwardingInvocation(
            receiver: receiver,
            arguments: [],
            effects: getterEffects
        )
        if requirement.contains("set") == false,
            getterEffects.contains("async") == false,
            getterEffects.contains("throws") == false
        {
            return "\(prefix)var \(name): \(type) { \(getter) }"
        }
        var accessors = ["get { \(getter) }"]
        if requirement.contains("set") {
            accessors.append(
                "set { \(forwardingInvocation(receiver: receiver, arguments: ["newValue"], effects: "")) }"
            )
        }
        return "\(prefix)var \(name): \(type) { \(accessors.joined(separator: " ")) }"
    }

    private func subscriptForwarder(_ requirement: String) -> String? {
        let receiver = "stub"
        guard let subscriptRange = requirement.range(of: "subscript"),
            let opening = requirement[subscriptRange.upperBound...].firstIndex(of: "("),
            let closing = matchingParen(in: requirement, opening: opening),
            let arrow = requirement[closing...].range(of: "->")
        else { return nil }
        let prefix = String(requirement[..<subscriptRange.lowerBound])
        let header = String(requirement[subscriptRange.lowerBound ..< arrow.upperBound])
        let tail = requirement[arrow.upperBound...]
        let type =
            tail.components(separatedBy: "{").first?.trimmingCharacters(
                in: .whitespaces
            ) ?? "Void"
        let arguments = invocationArguments(String(requirement[opening ... closing]))
        let getterEffects = effects(in: accessorSuffix(requirement, accessor: "get"))
        let getter = forwardingInvocation(
            receiver: receiver,
            arguments: arguments,
            effects: getterEffects
        )
        if requirement.contains("set") == false,
            getterEffects.contains("async") == false,
            getterEffects.contains("throws") == false
        {
            return "\(prefix)\(header) \(type) { \(getter) }"
        }
        var accessors = ["get { \(getter) }"]
        if requirement.contains("set") {
            accessors.append(
                "set { \(forwardingInvocation(receiver: receiver, arguments: arguments + ["newValue"], effects: "")) }"
            )
        }
        return "\(prefix)\(header) \(type) { \(accessors.joined(separator: " ")) }"
    }

    private func forwardingInvocation(
        receiver: String,
        arguments: [String],
        effects: String
    ) -> String {
        let isAsync = effects.contains("async")
        let isThrowing = effects.contains("throws")
        let method: String
        switch (isAsync, isThrowing) {
            case (false, false): method = "call"
            case (false, true): method = "throwingCall"
            case (true, false): method = "call"
            case (true, true): method = "throwingCall"
        }
        let prefix = [isThrowing ? "try" : nil, isAsync ? "await" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        var forwardedArguments = arguments
        if let failureType = typedFailureType(in: effects) {
            forwardedArguments.append("throwing: \(failureType).self")
        }
        let expression = [prefix, "\(receiver).\(method)(\(forwardedArguments.joined(separator: ", ")))"]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return expression
    }

    private func typedFailureType(in effects: String) -> String? {
        guard let throwsRange = effects.range(of: "throws(") else {
            return nil
        }
        let opening = effects.index(before: throwsRange.upperBound)
        guard let closing = matchingParen(in: effects, opening: opening) else {
            return nil
        }
        let failureType = effects[effects.index(after: opening) ..< closing]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return failureType.isEmpty ? nil : failureType
    }

    private func invocationArguments(_ parameters: String) -> [String] {
        let body = String(parameters.dropFirst().dropLast())
        return splitTopLevel(body, on: ",").compactMap { parameter in
            let declaration = parameter.trimmingCharacters(in: .whitespaces)
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let names = declaration[..<colon].split(whereSeparator: \.isWhitespace).map(
                String.init
            )
            guard let local = names.last else { return nil }
            let type = declaration[declaration.index(after: colon)...].trimmingCharacters(
                in: .whitespaces
            )
            return type.hasPrefix("inout ") ? "&\(local)" : local
        }
    }

    private func matchingParen(in value: String, opening: String.Index) -> String.Index? {
        var depth = 0
        for index in value[opening...].indices {
            if value[index] == "(" { depth += 1 }
            if value[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private func effects(in suffix: String) -> String {
        suffix.components(separatedBy: "->").first ?? suffix
    }

    private func accessorSuffix(_ requirement: String, accessor: String) -> String {
        guard let range = requirement.range(of: accessor) else { return "" }
        return String(requirement[range.upperBound...])
    }
}

private func splitTopLevel(_ value: String, on separator: Character) -> [String] {
    var components = [String]()
    var current = ""
    var depth = 0
    for character in value {
        switch character {
            case "(", "[", "<": depth += 1
            case ")", "]", ">": depth -= 1
            default: break
        }
        if character == separator, depth == 0 {
            components.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    if current.isEmpty == false { components.append(current) }
    return components
}

extension String {
    fileprivate var requirements: [String] {
        var result = [String]()
        var current = ""
        var parentheses = 0
        var braces = 0
        for line in components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false, trimmed.hasPrefix("//") == false else {
                continue
            }
            current += (current.isEmpty ? "" : " ") + trimmed
            parentheses += trimmed.filter { $0 == "(" }.count
            parentheses -= trimmed.filter { $0 == ")" }.count
            braces += trimmed.filter { $0 == "{" }.count
            braces -= trimmed.filter { $0 == "}" }.count
            if parentheses == 0, braces == 0 {
                result.append(current)
                current = ""
            }
        }
        return result
    }
}

package enum ManualStubGeneratorError: LocalizedError {
    case protocolNotFound(String)
    case unsupportedRequirement(requirement: String, reason: String)
    case duplicateProtocol(name: String, firstSource: String, secondSource: String)
    case noEligibleProtocols

    package var requirement: String? {
        switch self {
            case .protocolNotFound, .duplicateProtocol, .noEligibleProtocols:
                nil
            case .unsupportedRequirement(let requirement, _):
                requirement
        }
    }

    package var errorDescription: String? {
        switch self {
            case .protocolNotFound(let name):
                "could not find a complete protocol declaration for \(name)"
            case .unsupportedRequirement(let requirement, let reason):
                "cannot generate manual forwarding for `\(requirement)`: \(reason)"
            case .duplicateProtocol(let name, let firstSource, let secondSource):
                "found protocol \(name) in both \(firstSource) and \(secondSource)"
            case .noEligibleProtocols:
                "found no protocols whose requirements can be generated"
        }
    }
}
