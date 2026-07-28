#!/usr/bin/env swift

import Foundation

/// Generates routine instance-method forwarding for a `ManualStub`.
///
/// Usage:
///   swift Scripts/generate-manual-stub.swift ServiceProtocol Sources/Service.swift
///
/// The generated declaration is ordinary Swift source: check it into a test
/// target, then extend it manually for properties, subscripts, static
/// requirements, or initializers. Keeping the generator opt-in avoids a macro
/// or build-tool dependency for consumers that do not need it.
guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate-manual-stub.swift <ProtocolName> <source.swift>\n", stderr)
    exit(64)
}

let protocolName = CommandLine.arguments[1]
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let source: String
do {
    source = try String(contentsOf: sourceURL, encoding: .utf8)
} catch {
    fputs("could not read \(sourceURL.path): \(error)\n", stderr)
    exit(66)
}

let lines = source.components(separatedBy: .newlines)
guard
    let declarationIndex = lines.firstIndex(where: {
        $0.contains("protocol \(protocolName)")
    })
else {
    fputs("could not find protocol \(protocolName)\n", stderr)
    exit(65)
}

var depth = 0
var requirements: [String] = []
for line in lines[declarationIndex...] {
    depth += line.filter { $0 == "{" }.count
    depth -= line.filter { $0 == "}" }.count
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("func ") {
        requirements.append(trimmed)
    }
    if depth == 0, line != lines[declarationIndex] {
        break
    }
}

func arguments(from parameters: String) -> String {
    let body = String(parameters.dropFirst().dropLast())
    guard body.trimmingCharacters(in: .whitespaces).isEmpty == false else { return "" }
    return body.split(separator: ",").map { parameter in
        let declaration = parameter.trimmingCharacters(in: .whitespaces)
        let beforeType = declaration.split(separator: ":", maxSplits: 1)[0]
            .trimmingCharacters(in: .whitespaces)
        let names = beforeType.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let localName = names.last else { return declaration }
        guard names.first != "_" else { return localName }
        let label = names.count > 1 ? names[0] : localName
        return "\(label): \(localName)"
    }.joined(separator: ", ")
}

func implementation(for requirement: String) -> String? {
    guard
        let open = requirement.firstIndex(of: "("),
        let close = requirement[open...].firstIndex(of: ")")
    else {
        return nil
    }
    let head = requirement[..<open]
    guard let name = head.split(separator: " ").last else { return nil }
    let parameters = String(requirement[open ... close])
    let isAsync = requirement[close...].contains("async")
    let isThrowing = requirement[close...].contains("throws")
    let prefix = [isThrowing ? "try" : nil, isAsync ? "await" : nil]
        .compactMap { $0 }
        .joined(separator: " ")
    let invocation = "stub\(isThrowing ? ".throwing" : "").\(name)(\(arguments(from: parameters)))"
    let body = ([prefix, invocation].filter { $0.isEmpty == false }).joined(separator: " ")
    return "    \(requirement) { \(body) }"
}

let implementations = requirements.compactMap(implementation)
guard implementations.isEmpty == false else {
    fputs("no instance method requirements found in \(protocolName)\n", stderr)
    exit(65)
}

print(
    """
    import TestDoubles

    struct \(protocolName)ManualStub: \(protocolName), StubConformer {
        let stub: ManualStub<Self>

    \(implementations.joined(separator: "\n"))
    }
    """)
