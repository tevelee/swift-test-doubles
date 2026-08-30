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
        let accessPrefix = restrictedAccessPrefix()
        var members = [
            "typealias StubbedProtocol = any \(protocolName)",
            compilerEvidenceMember(
                declaration: declaration,
                requirements: requirements
            ),
            declaration.inheritsActor
                ? "let stub: CompiledStub<\(conformerName)>\n\n    init(stub: CompiledStub<\(conformerName)>) { self.stub = stub }"
                : "let stub: CompiledStub<Self>",
            "static func eraseToStubbedProtocol(_ conformer: \(conformerName)) -> StubbedProtocol { conformer }"
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
            \(importBlock)\(accessPrefix)\(conformerKind) \(conformerName): \(protocolName), AutomaticStubConformer {
                \(members.joined(separator: "\n\n    "))
            }

            \(accessPrefix)typealias \(stubName) = CompiledStub<\(conformerName)>
            """ + "\n"
    }

    private struct DescribedRequirement {
        let name: String
        let kind: String
        let expression: String?
    }

    private func compilerEvidenceMember(
        declaration: SwiftProtocolDeclaration,
        requirements: [String]
    ) -> String {
        let described = requirements.flatMap(sourceRequirements)
        let expressions = described.compactMap(\.expression)
        let hasCompleteDescription =
            expressions.count == callableRequirementCount(in: requirements)
            && requirements.allSatisfy(isCallableRequirement)
            && declaration.inheritedTypeNames.allSatisfy {
                ["Actor", "AnyObject", "Sendable"].contains($0)
            }
        let actorReason = "Actor protocols require a genuine actor instance."
        let runtimeConstruction: String
        if declaration.inheritsActor {
            runtimeConstruction = ".unavailable(reason: \"\(actorReason)\")"
        } else if hasCompleteDescription {
            let expressions = expressions.map { "            \($0)" }
                .joined(separator: ",\n")
            runtimeConstruction = ".requirements([\n\(expressions)\n        ])"
        } else {
            runtimeConstruction = ".automaticDiscovery"
        }
        let support = described.enumerated().map { index, requirement in
            let runtimeEligibility: String
            if declaration.inheritsActor {
                runtimeEligibility = ".unavailable(reason: \"\(actorReason)\")"
            } else if requirement.expression != nil {
                runtimeEligibility = ".compilerDescribed"
            } else {
                runtimeEligibility = ".requiresRuntimeDiscovery"
            }
            return [
                "                StubRequirementSupport(",
                "                    declaringProtocol: \"\(protocolName)\",",
                "                    name: \"\(requirement.name)\",",
                "                    kind: .\(requirement.kind),",
                "                    declarationIndex: \(index),",
                "                    runtimeEligibility: \(runtimeEligibility),",
                "                    compiledEligibility: .generatedConformer",
                "                )"
            ].joined(separator: "\n")
        }.joined(separator: ",\n")
        return [
            "static let compilerEvidence: StubCompilerEvidence<StubbedProtocol> = StubCompilerEvidence(",
            "        runtimeConstruction: \(runtimeConstruction),",
            "        compiledFallbackEligibility: .generatedConformer,",
            "        sourceSupport: StubSourceSupportReport(",
            "            protocolName: \"\(protocolName)\",",
            "            requirements: [",
            support,
            "            ]",
            "        )",
            ")"
        ].joined(separator: "\n")
    }

    private func callableRequirementCount(in requirements: [String]) -> Int {
        requirements.reduce(into: 0) { count, requirement in
            if isFunctionRequirement(requirement) {
                count += 1
            } else if isPropertyRequirement(requirement) || isSubscriptRequirement(requirement) {
                count += requirement.contains("set") ? 2 : 1
            }
        }
    }

    private func isCallableRequirement(_ requirement: String) -> Bool {
        isFunctionRequirement(requirement)
            || isPropertyRequirement(requirement)
            || isSubscriptRequirement(requirement)
    }

    private func isFunctionRequirement(_ requirement: String) -> Bool {
        requirement.contains(" func ") || requirement.hasPrefix("func ")
            || requirement.hasPrefix("static func ")
            || requirement.hasPrefix("class func ")
    }

    private func isPropertyRequirement(_ requirement: String) -> Bool {
        requirement.contains(" var ") || requirement.hasPrefix("var ")
            || requirement.hasPrefix("static var ")
            || requirement.hasPrefix("class var ")
    }

    private func isSubscriptRequirement(_ requirement: String) -> Bool {
        requirement.contains("subscript")
    }

    private func describedRequirements(_ requirement: String) -> [DescribedRequirement] {
        if isFunctionRequirement(requirement) {
            return describedFunction(requirement).map { [$0] } ?? []
        }
        if isPropertyRequirement(requirement) {
            return describedProperty(requirement) ?? []
        }
        if isSubscriptRequirement(requirement) {
            return describedSubscript(requirement) ?? []
        }
        return []
    }

    private func sourceRequirements(_ requirement: String) -> [DescribedRequirement] {
        let described = describedRequirements(requirement)
        if described.isEmpty == false { return described }
        if let funcRange = requirement.range(of: "func "),
            let opening = requirement[funcRange.upperBound...].firstIndex(of: "("),
            let closing = matchingParen(in: requirement, opening: opening)
        {
            let baseName =
                requirement[funcRange.upperBound ..< opening]
                .split(separator: "<").first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "method"
            let labels = parameterLabels(in: requirement[opening ... closing])
            return [
                DescribedRequirement(
                    name: labels.isEmpty
                        ? "\(baseName)()"
                        : "\(baseName)(\(labels.map { "\($0):" }.joined()))",
                    kind: "method",
                    expression: nil
                )
            ]
        }
        if let varRange = requirement.range(of: "var ") {
            let tail = requirement[varRange.upperBound...]
            let name =
                tail.split(separator: ":", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "property"
            var result = [DescribedRequirement(name: name, kind: "getter", expression: nil)]
            if requirement.contains("set") {
                result.append(
                    DescribedRequirement(name: name, kind: "setter", expression: nil)
                )
            }
            return result
        }
        if requirement.contains("subscript") {
            var result = [
                DescribedRequirement(name: "subscript", kind: "getter", expression: nil)
            ]
            if requirement.contains("set") {
                result.append(
                    DescribedRequirement(name: "subscript", kind: "setter", expression: nil)
                )
            }
            return result
        }
        return []
    }

    private func describedFunction(_ requirement: String) -> DescribedRequirement? {
        guard let funcRange = requirement.range(of: "func "),
            let opening = requirement[funcRange.upperBound...].firstIndex(of: "("),
            let closing = matchingParen(in: requirement, opening: opening),
            requirement[funcRange.upperBound ..< opening].contains("<") == false,
            let parameterTypes = parameterTypes(in: requirement[opening ... closing])
        else { return nil }
        let suffix = String(requirement[closing...])
        guard let resultType = resultType(in: suffix) else { return nil }
        let effects = effects(in: suffix)
        let isAsync = effects.contains("async")
        let isThrowing = effects.contains("throws")
        let arguments = parameterTypes.map(metatype).joined(separator: ", ")
        let prefix = arguments.isEmpty ? "" : "\(arguments), "
        let expression: String
        if let failureType = typedFailureType(in: effects) {
            expression = ".method(\(prefix)returning: \(metatype(resultType)), throwing: \(metatype(failureType))\(isAsync ? ", isAsync: true" : ""))"
        } else {
            var options = [String]()
            if isThrowing { options.append("isThrowing: true") }
            if isAsync { options.append("isAsync: true") }
            let optionSuffix = options.isEmpty ? "" : ", \(options.joined(separator: ", "))"
            expression = ".method(\(prefix)returning: \(metatype(resultType))\(optionSuffix))"
        }
        let baseName = requirement[funcRange.upperBound ..< opening]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = parameterLabels(in: requirement[opening ... closing])
        return DescribedRequirement(
            name: labels.isEmpty ? "\(baseName)()" : "\(baseName)(\(labels.map { "\($0):" }.joined()))",
            kind: "method",
            expression: expression
        )
    }

    private func describedProperty(_ requirement: String) -> [DescribedRequirement]? {
        let bodyless =
            requirement.components(separatedBy: "{").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? requirement
        guard let varRange = bodyless.range(of: "var "),
            let colon = bodyless[varRange.upperBound...].firstIndex(of: ":")
        else { return nil }
        let name = bodyless[varRange.upperBound ..< colon]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let type = bodyless[bodyless.index(after: colon)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafelySpelledType(type), requirement.contains("get") else { return nil }
        let getterEffects = effects(in: accessorSuffix(requirement, accessor: "get"))
        guard typedFailureType(in: getterEffects) == nil else { return nil }
        var options = [String]()
        if getterEffects.contains("throws") { options.append("isThrowing: true") }
        if getterEffects.contains("async") { options.append("isAsync: true") }
        let optionSuffix = options.isEmpty ? "" : ", \(options.joined(separator: ", "))"
        var result = [
            DescribedRequirement(
                name: name,
                kind: "getter",
                expression: ".getter(\(metatype(type))\(optionSuffix))"
            )
        ]
        if requirement.contains("set") {
            result.append(
                DescribedRequirement(
                    name: name,
                    kind: "setter",
                    expression: ".setter(\(metatype(type)))"
                )
            )
        }
        return result
    }

    private func describedSubscript(_ requirement: String) -> [DescribedRequirement]? {
        guard let subscriptRange = requirement.range(of: "subscript"),
            let opening = requirement[subscriptRange.upperBound...].firstIndex(of: "("),
            let closing = matchingParen(in: requirement, opening: opening),
            let arrow = requirement[closing...].range(of: "->"),
            let parameterTypes = parameterTypes(in: requirement[opening ... closing])
        else { return nil }
        let result =
            requirement[arrow.upperBound...]
            .components(separatedBy: "{").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isSafelySpelledType(result) else { return nil }
        let getterEffects = effects(in: accessorSuffix(requirement, accessor: "get"))
        guard typedFailureType(in: getterEffects) == nil else { return nil }
        let indices = parameterTypes.map(metatype).joined(separator: ", ")
        let indexPrefix = indices.isEmpty ? "" : "\(indices), "
        var options = [String]()
        if getterEffects.contains("throws") { options.append("isThrowing: true") }
        if getterEffects.contains("async") { options.append("isAsync: true") }
        let optionSuffix = options.isEmpty ? "" : ", \(options.joined(separator: ", "))"
        var descriptions = [
            DescribedRequirement(
                name: "subscript",
                kind: "getter",
                expression: ".subscriptGetter(indexedBy: \(indexPrefix)returning: \(metatype(result))\(optionSuffix))"
            )
        ]
        if requirement.contains("set") {
            descriptions.append(
                DescribedRequirement(
                    name: "subscript",
                    kind: "setter",
                    expression: ".subscriptSetter(indexedBy: \(indexPrefix)assigning: \(metatype(result)))"
                )
            )
        }
        return descriptions
    }

    private func parameterTypes(in parameters: Substring) -> [String]? {
        let body = String(parameters.dropFirst().dropLast())
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var result = [String]()
        for parameter in splitTopLevel(body, on: ",") {
            guard let colon = parameter.firstIndex(of: ":") else { return nil }
            let type = parameter[parameter.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafelySpelledType(type), type.hasPrefix("inout ") == false else {
                return nil
            }
            result.append(type)
        }
        return result
    }

    private func parameterLabels(in parameters: Substring) -> [String] {
        let body = String(parameters.dropFirst().dropLast())
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }
        return splitTopLevel(body, on: ",").compactMap { parameter in
            guard let colon = parameter.firstIndex(of: ":") else { return nil }
            return parameter[..<colon].split(whereSeparator: \.isWhitespace).first.map(String.init)
        }
    }

    private func resultType(in suffix: String) -> String? {
        guard let arrow = suffix.range(of: "->") else { return "Void" }
        let type =
            suffix[arrow.upperBound...]
            .components(separatedBy: " where ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return isSafelySpelledType(type) ? type : nil
    }

    private func isSafelySpelledType(_ type: String) -> Bool {
        type.isEmpty == false
            && type.contains("...") == false
            && type.contains("=") == false
            && type.contains("@") == false
            && type.contains("Self") == false
            && type.contains("some ") == false
            && type.contains("each ") == false
            && type.hasPrefix("isolated ") == false
            && type.hasPrefix("borrowing ") == false
            && type.hasPrefix("consuming ") == false
    }

    private func metatype(_ type: String) -> String {
        type.hasPrefix("any ") ? "(\(type)).self" : "\(type).self"
    }

    private func restrictedAccessPrefix() -> String {
        let normalized = source.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if normalized.contains("fileprivate protocol \(protocolName)") {
            return "fileprivate "
        }
        if normalized.contains("private protocol \(protocolName)") {
            return "private "
        }
        return ""
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
