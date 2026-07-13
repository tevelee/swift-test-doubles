#if RUNTIME_STUB
import Echo
import Foundation

enum ModuleSignatureDiscovery {
    static func discover(
        protocolName: String,
        moduleName: String,
        proto: ProtocolDescriptor
    ) throws -> [DiscoveredSignature] {
        let graph = try loadSymbolGraph(moduleName: moduleName, protocolName: protocolName)
        guard let protocolSymbol = graph.symbols.first(where: {
            $0.kind.identifier == "swift.protocol" &&
            $0.pathComponents.last == protocolName
        }) else {
            throw RuntimeStubError.moduleSignatureNotFound(
                protocolName: protocolName,
                moduleName: moduleName
            )
        }

        let requirementIDs = Set(graph.relationships.compactMap { relationship -> String? in
            relationship.kind == "requirementOf" && relationship.target == protocolSymbol.identifier.precise
                ? relationship.source
                : nil
        })

        let requirementSymbols = graph.symbols.filter { requirementIDs.contains($0.identifier.precise) }
            .filter { $0.kind.identifier == "swift.method" || $0.kind.identifier == "swift.property" }
        let mockableIndices = mockableRequirementIndices(for: proto)

        guard requirementSymbols.count == mockableIndices.count else {
            throw RuntimeStubError.slotCountMismatch(
                protocolName: protocolName,
                expected: mockableIndices.count,
                actual: requirementSymbols.count
            )
        }

        return zip(requirementSymbols, mockableIndices).map { symbol, slot in
            let requirementKind = proto.requirements[slot].flags.kind
            return discoveredSignature(
                from: symbol,
                slot: slot,
                kind: requirementKind,
                moduleName: moduleName
            )
        }
    }

    private static func discoveredSignature(
        from symbol: Symbol,
        slot: Int,
        kind: ProtocolRequirement.Kind,
        moduleName: String
    ) -> DiscoveredSignature {
        let title = symbol.names.title
        let declaration = declarationText(for: symbol)
        let isThrowing = declaration.contains(" throws") || declaration.contains(" rethrows")
        let isAsync = declaration.contains(" async")

        switch symbol.kind.identifier {
        case "swift.property":
            let type = propertyType(from: symbol, moduleName: moduleName)
            return DiscoveredSignature(
                slot: slot,
                kind: kind,
                methodName: title,
                ret: type.simple,
                isThrowing: false,
                isAsync: false,
                rawDemangled: "symbolgraph:\(symbol.identifier.precise)",
                qualifiedRet: type.qualified
            )

        default:
            let parameters = symbol.functionSignature?.parameters ?? []
            let args = parameters.map { parameterType(from: $0, moduleName: moduleName) }
            let returnType = returnType(from: symbol, moduleName: moduleName)
            return DiscoveredSignature(
                slot: slot,
                kind: kind,
                methodName: title,
                args: args.map(\.simple),
                ret: returnType.simple,
                isThrowing: isThrowing,
                isAsync: isAsync,
                rawDemangled: "symbolgraph:\(symbol.identifier.precise)",
                paramLabels: parameterLabels(from: title),
                qualifiedArgs: args.map(\.qualified),
                qualifiedRet: returnType.qualified
            )
        }
    }

    private static func loadSymbolGraph(
        moduleName: String,
        protocolName: String
    ) throws -> SymbolGraph {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-test-doubles-symbolgraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let swift = toolPath("swift")
        var arguments = [
            "symbolgraph-extract",
            "-module-name", moduleName,
            "-output-dir", outputDirectory.path,
            "-minimum-access-level", "public",
        ]
        if let target = targetTriple() {
            arguments += ["-target", target]
        }
        for path in importPaths() {
            arguments += ["-I", path]
        }
        if let sdk = sdkPath(), sdk.isEmpty == false {
            arguments += ["-sdk", sdk]
        }

        let result = run(swift, arguments)
        guard result.status == 0 else {
            throw RuntimeStubError.moduleSignatureDiscoveryFailed(
                protocolName: protocolName,
                moduleName: moduleName,
                details: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        let exactPath = outputDirectory.appendingPathComponent("\(moduleName).symbols.json")
        let graphURL: URL
        if FileManager.default.fileExists(atPath: exactPath.path) {
            graphURL = exactPath
        } else {
            let candidates = (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            guard let candidate = candidates.first(where: { $0.lastPathComponent.hasSuffix(".symbols.json") }) else {
                throw RuntimeStubError.moduleSignatureDiscoveryFailed(
                    protocolName: protocolName,
                    moduleName: moduleName,
                    details: "symbolgraph-extract did not emit a .symbols.json file"
                )
            }
            graphURL = candidate
        }

        do {
            let data = try Data(contentsOf: graphURL)
            return try JSONDecoder().decode(SymbolGraph.self, from: data)
        } catch {
            throw RuntimeStubError.moduleSignatureDiscoveryFailed(
                protocolName: protocolName,
                moduleName: moduleName,
                details: "Failed to decode \(graphURL.lastPathComponent): \(error)"
            )
        }
    }

    private static func parameterType(from parameter: Symbol.Parameter, moduleName: String) -> TypeNames {
        let fragments = fragmentsAfterColon(parameter.declarationFragments)
        return typeNames(from: fragments, moduleName: moduleName)
    }

    private static func returnType(from symbol: Symbol, moduleName: String) -> TypeNames {
        guard let fragments = symbol.functionSignature?.returns, fragments.isEmpty == false else {
            return TypeNames(simple: "Void", qualified: "Swift.Void")
        }
        return typeNames(from: fragments, moduleName: moduleName)
    }

    private static func propertyType(from symbol: Symbol, moduleName: String) -> TypeNames {
        let declaration = declarationText(for: symbol)
        guard let colon = declaration.range(of: ":") else {
            return TypeNames(simple: "Void", qualified: "Swift.Void")
        }
        let suffix = declaration[colon.upperBound...]
        let typeText = suffix
            .split(separator: "{", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Void"
        return typeNames(from: typeText, moduleName: moduleName)
    }

    private static func fragmentsAfterColon(_ fragments: [Symbol.Fragment]) -> [Symbol.Fragment] {
        guard let colonIndex = fragments.firstIndex(where: { $0.spelling.contains(":") }) else {
            return fragments
        }
        return Array(fragments.suffix(from: fragments.index(after: colonIndex)))
    }

    private static func typeNames(from fragments: [Symbol.Fragment], moduleName: String) -> TypeNames {
        typeNames(from: fragments.map(\.spelling).joined(), moduleName: moduleName)
    }

    private static func typeNames(from raw: String, moduleName: String) -> TypeNames {
        let simple = raw
            .replacingOccurrences(of: "Swift.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = simple == "()" ? "Void" : simple
        return TypeNames(simple: normalized, qualified: qualifiedTypeName(normalized, moduleName: moduleName))
    }

    private static func qualifiedTypeName(_ typeName: String, moduleName: String) -> String {
        switch typeName {
        case "Void", "()": return "Swift.Void"
        case "Int": return "Swift.Int"
        case "String": return "Swift.String"
        case "Bool": return "Swift.Bool"
        case "Double": return "Swift.Double"
        case "Float": return "Swift.Float"
        default:
            if typeName.hasPrefix("["),
               typeName.hasSuffix("]") {
                let inner = String(typeName.dropFirst().dropLast())
                return "[\(qualifiedTypeName(inner, moduleName: moduleName))]"
            }
            if typeName.contains(".") {
                return typeName
            }
            return "\(moduleName).\(typeName)"
        }
    }

    private static func parameterLabels(from methodTitle: String) -> [String] {
        guard let open = methodTitle.firstIndex(of: "("),
              let close = methodTitle.lastIndex(of: ")"),
              open < close else {
            return []
        }
        let labelsText = methodTitle[methodTitle.index(after: open)..<close]
        guard labelsText.isEmpty == false else {
            return []
        }
        return labelsText.split(separator: ":", omittingEmptySubsequences: false)
            .dropLast()
            .map { label in
                let text = String(label)
                return text.isEmpty ? "_" : text
            }
    }

    private static func declarationText(for symbol: Symbol) -> String {
        symbol.declarationFragments.map(\.spelling).joined()
    }

    private static func mockableRequirementIndices(for proto: ProtocolDescriptor) -> [Int] {
        proto.requirements.enumerated().compactMap { i, req -> Int? in
            switch req.flags.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return nil
            default:
                return i
            }
        }
    }

    private static func importPaths() -> [String] {
        var paths: [String] = []
        func append(_ path: String) {
            guard FileManager.default.fileExists(atPath: path),
                  paths.contains(path) == false else {
                return
            }
            paths.append(path)
        }

        for key in ["BUILT_PRODUCTS_DIR", "TARGET_BUILD_DIR", "CONFIGURATION_BUILD_DIR", "BUILD_DIR"] {
            if let path = ProcessInfo.processInfo.environment[key] {
                append(path)
                append("\(path)/Modules")
            }
        }

        let executableDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
        for directory in ancestorDirectories(startingAt: executableDir, limit: 10) {
            append(directory.path)
            append(directory.appendingPathComponent("Modules").path)
        }

        let cwd = FileManager.default.currentDirectoryPath
        for path in [
            "\(cwd)/.build/arm64-apple-macosx/debug",
            "\(cwd)/.build/arm64e-apple-macosx/debug",
            "\(cwd)/.build/x86_64-apple-macosx/debug",
            "\(cwd)/.build/x86_64-unknown-linux-gnu/debug",
            "\(cwd)/.build/aarch64-unknown-linux-gnu/debug",
            "\(cwd)/.build/debug",
        ] {
            append(path)
            append("\(path)/Modules")
        }

        return paths
    }

    private static func targetTriple() -> String? {
        let result = run(toolPath("swiftc"), ["-print-target-info"])
        guard result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let target = json["target"] as? [String: Any],
              let triple = target["triple"] as? String else {
            return nil
        }
        return triple
    }

    private static func sdkPath() -> String? {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
            return nil
        }
        let result = run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"])
        return result.status == 0 ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    private static func toolPath(_ name: String) -> String {
        for candidate in environmentToolCandidates(name) where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let result = run("/usr/bin/which", [name])
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0, path.isEmpty == false {
            return path
        }

        if FileManager.default.fileExists(atPath: "/usr/bin/xcrun") {
            let result = run("/usr/bin/xcrun", ["--find", name])
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.status == 0, path.isEmpty == false {
                return path
            }
        }

        return name
    }

    private static func environmentToolCandidates(_ name: String) -> [String] {
        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if name == "swiftc", let swiftExec = env["SWIFT_EXEC"] {
            candidates.append(swiftExec)
        }
        if name == "swift",
           let swiftExec = env["SWIFT_EXEC"],
           swiftExec.hasSuffix("/swiftc") {
            candidates.append(String(swiftExec.dropLast(1)))
        }

        for key in ["TOOLCHAIN_DIR", "DT_TOOLCHAIN_DIR"] {
            if let dir = env[key] {
                candidates.append("\(dir)/usr/bin/\(name)")
            }
        }
        if let developerDir = env["DEVELOPER_DIR"] {
            candidates.append("\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/bin/\(name)")
        }

        return candidates
    }

    private static func run(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            return ProcessResult(
                status: process.terminationStatus,
                stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(status: -1, stdout: "", stderr: "\(error)")
        }
    }

    private static func ancestorDirectories(startingAt url: URL, limit: Int) -> [URL] {
        var result: [URL] = []
        var current = url
        for _ in 0..<limit {
            result.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return result
    }
}

private struct TypeNames {
    let simple: String
    let qualified: String
}

private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private struct SymbolGraph: Decodable {
    let symbols: [Symbol]
    let relationships: [Relationship]
}

private struct Relationship: Decodable {
    let source: String
    let target: String
    let kind: String
}

private struct Symbol: Decodable {
    let kind: Kind
    let identifier: Identifier
    let pathComponents: [String]
    let names: Names
    let functionSignature: FunctionSignature?
    let declarationFragments: [Fragment]

    struct Kind: Decodable {
        let identifier: String
    }

    struct Identifier: Decodable {
        let precise: String
    }

    struct Names: Decodable {
        let title: String
    }

    struct FunctionSignature: Decodable {
        let parameters: [Parameter]?
        let returns: [Fragment]?
    }

    struct Parameter: Decodable {
        let declarationFragments: [Fragment]
    }

    struct Fragment: Decodable {
        let spelling: String
    }
}
#endif
