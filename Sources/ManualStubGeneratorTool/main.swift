import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: ManualStubGeneratorTool <ProtocolName> <source.swift> <output.swift>\n", stderr)
    exit(64)
}

let protocolName = CommandLine.arguments[1]
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

do {
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let output = try Generator(protocolName: protocolName, source: source).render()
    try output.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    fputs("ManualStub generation failed: \(error.localizedDescription)\n", stderr)
    exit(65)
}

private struct Generator {
    let protocolName: String
    let source: String

    func render() throws -> String {
        let requirements = try protocolBody().requirements
        let usesStaticStore = requirements.contains { requirement in
            requirement.hasPrefix("static ") || requirement.hasPrefix("class ")
                || requirement.hasPrefix("init")
        }
        var members = [
            "let stub: ManualStub<Self>",
            "init(stub: ManualStub<Self>) { self.stub = stub }"
        ]
        if usesStaticStore {
            members.append("static let staticStub = ManualStub<Self>()")
        }
        for requirement in requirements {
            if let member = forwarder(for: requirement) {
                members.append(member)
            }
        }
        return """
            import TestDoubles

            struct \(protocolName)ManualStub: \(protocolName), StubConformer {
                \(members.joined(separator: "\n\n    "))
            }
            """
    }

    private func protocolBody() throws -> String {
        guard let declaration = source.range(of: "protocol \(protocolName)") else {
            throw GeneratorError.protocolNotFound(protocolName)
        }
        guard let opening = source[declaration.lowerBound...].firstIndex(of: "{") else {
            throw GeneratorError.protocolNotFound(protocolName)
        }
        var depth = 0
        for index in source[opening...].indices {
            switch source[index] {
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(source[source.index(after: opening) ..< index])
                    }
                default: break
            }
        }
        throw GeneratorError.protocolNotFound(protocolName)
    }

    private func forwarder(for requirement: String) -> String? {
        if requirement.contains(" func ") || requirement.hasPrefix("func ") || requirement.hasPrefix("static func ") || requirement.hasPrefix("class func ") {
            return functionForwarder(requirement)
        }
        if requirement.contains(" var ") || requirement.hasPrefix("var ") || requirement.hasPrefix("static var ") || requirement.hasPrefix("class var ") {
            return propertyForwarder(requirement)
        }
        if requirement.contains("subscript") {
            return subscriptForwarder(requirement)
        }
        if requirement.hasPrefix("init") {
            return "\(requirement) { stub = Self.staticStub }"
        }
        return nil
    }

    private func functionForwarder(_ requirement: String) -> String? {
        guard let funcRange = requirement.range(of: "func ") else { return nil }
        let prefix = String(requirement[..<funcRange.lowerBound])
        let isStatic = prefix.contains("static") || prefix.contains("class")
        let receiver = isStatic ? "Self.staticStub" : "stub"
        guard let opening = requirement[funcRange.upperBound...].firstIndex(of: "(") else { return nil }
        guard let closing = matchingParen(in: requirement, opening: opening) else { return nil }
        let arguments = invocationArguments(String(requirement[opening ... closing]))
        let suffix = String(requirement[closing...])
        let effects = effects(in: suffix)
        let returnType = returnType(in: suffix)
        return "\(requirement) { \(forwardingInvocation(receiver: receiver, arguments: arguments, effects: effects, returnType: returnType)) }"
    }

    private func propertyForwarder(_ requirement: String) -> String? {
        let isStatic = requirement.hasPrefix("static ") || requirement.hasPrefix("class ")
        let receiver = isStatic ? "Self.staticStub" : "stub"
        let prefix = isStatic ? (requirement.hasPrefix("static ") ? "static " : "class ") : ""
        let bodyless = requirement.components(separatedBy: "{").first?.trimmingCharacters(in: .whitespaces) ?? requirement
        guard let varRange = bodyless.range(of: "var "), let colon = bodyless[varRange.upperBound...].firstIndex(of: ":") else { return nil }
        let name = bodyless[varRange.upperBound ..< colon].trimmingCharacters(in: .whitespaces)
        let type = bodyless[bodyless.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard requirement.contains("get") else { return nil }
        let getter = forwardingInvocation(
            receiver: receiver,
            arguments: [],
            effects: effects(in: accessorSuffix(requirement, accessor: "get")),
            returnType: type
        )
        var accessors = ["get { \(getter) }"]
        if requirement.contains("set") {
            accessors.append("set { \(receiver).call(newValue) }")
        }
        return "\(prefix)var \(name): \(type) { \(accessors.joined(separator: " ")) }"
    }

    private func subscriptForwarder(_ requirement: String) -> String? {
        let isStatic = requirement.hasPrefix("static ") || requirement.hasPrefix("class ")
        let receiver = isStatic ? "Self.staticStub" : "stub"
        let prefix = isStatic ? (requirement.hasPrefix("static ") ? "static " : "class ") : ""
        guard let subscriptRange = requirement.range(of: "subscript"), let opening = requirement[subscriptRange.upperBound...].firstIndex(of: "("), let closing = matchingParen(in: requirement, opening: opening),
            let arrow = requirement[closing...].range(of: "->")
        else { return nil }
        let header = String(requirement[subscriptRange.lowerBound ..< arrow.upperBound])
        let tail = requirement[arrow.upperBound...]
        let type = tail.components(separatedBy: "{").first?.trimmingCharacters(in: .whitespaces) ?? "Void"
        let arguments = invocationArguments(String(requirement[opening ... closing]))
        let getter = forwardingInvocation(
            receiver: receiver,
            arguments: arguments,
            effects: effects(in: accessorSuffix(requirement, accessor: "get")),
            returnType: type
        )
        var accessors = ["get { \(getter) }"]
        if requirement.contains("set") {
            accessors.append("set { \(receiver).call(\((arguments + ["newValue"]).joined(separator: ", "))) }")
        }
        return "\(prefix)\(header) \(type) { \(accessors.joined(separator: " ")) }"
    }

    private func forwardingInvocation(
        receiver: String,
        arguments: [String],
        effects: String,
        returnType: String
    ) -> String {
        let isAsync = effects.contains("async")
        let isThrowing = effects.contains("throws")
        let method: String
        switch (isAsync, isThrowing) {
            case (false, false): method = "call"
            case (false, true): method = "throwingCall"
            case (true, false): method = "asyncCall"
            case (true, true): method = "asyncThrowingCall"
        }
        let prefix = [isThrowing ? "try" : nil, isAsync ? "await" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        let expression = [prefix, "\(receiver).\(method)(\(arguments.joined(separator: ", ")))"]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return returnType == "Void" || returnType == "()" ? expression : "return \(expression)"
    }

    private func invocationArguments(_ parameters: String) -> [String] {
        let body = String(parameters.dropFirst().dropLast())
        return splitTopLevel(body, on: ",").compactMap { parameter in
            let declaration = parameter.trimmingCharacters(in: .whitespaces)
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let names = declaration[..<colon].split(whereSeparator: \.isWhitespace).map(String.init)
            guard let local = names.last else { return nil }
            let type = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
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

    private func returnType(in suffix: String) -> String {
        guard let arrow = suffix.range(of: "->") else { return "Void" }
        return suffix[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
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
            guard trimmed.isEmpty == false, trimmed.hasPrefix("//") == false else { continue }
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

private enum GeneratorError: LocalizedError {
    case protocolNotFound(String)

    var errorDescription: String? {
        switch self {
            case .protocolNotFound(let name): "could not find a complete protocol declaration for \(name)"
        }
    }
}
