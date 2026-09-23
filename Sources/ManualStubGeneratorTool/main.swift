import Foundation
import ManualStubGeneratorCore

func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

let usage = """
    usage:
      ManualStubGeneratorTool <protocol-name> <input-swift-file> <output-swift-file> [options]
      ManualStubGeneratorTool --all <input-swift-file-or-directory> <output-swift-file> [options]

    options:
      --import <Module>                Import a module in the generated file.
      --testable-import <Module>       Import a module with @testable in the generated file.
      --module-source <Module> <path>  Also generate stubs for protocols declared in
                                       another module's sources (--all only).
    """

var positional = [String]()
var additionalImports = [String]()
var moduleSources = [(module: String, url: URL)]()
var remaining = CommandLine.arguments.dropFirst()[...]
while let argument = remaining.popFirst() {
    switch argument {
        case "--import", "--testable-import":
            guard let module = remaining.popFirst() else {
                writeError(usage)
                exit(64)
            }
            additionalImports.append(
                argument == "--import" ? "import \(module)" : "@testable import \(module)"
            )
        case "--module-source":
            guard let module = remaining.popFirst(), let path = remaining.popFirst() else {
                writeError(usage)
                exit(64)
            }
            moduleSources.append((module, URL(fileURLWithPath: path).standardizedFileURL))
        default:
            positional.append(argument)
    }
}

guard positional.count == 3 else {
    writeError(usage)
    exit(64)
}

let selection = positional[0]
let inputURL = URL(fileURLWithPath: positional[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: positional[2]).standardizedFileURL

do {
    let output: String
    if selection == "--all" {
        guard inputURL != outputURL else {
            throw ToolError.outputOverwritesInput
        }
        var sources = try sourceFiles(at: inputURL, excluding: outputURL).map {
            try ManualStubBatchGenerator.Source(
                identifier: $0.path,
                contents: String(contentsOf: $0, encoding: .utf8)
            )
        }
        for moduleSource in moduleSources {
            sources += try sourceFiles(at: moduleSource.url, excluding: outputURL).map {
                try ManualStubBatchGenerator.Source(
                    identifier: $0.path,
                    contents: String(contentsOf: $0, encoding: .utf8),
                    module: moduleSource.module
                )
            }
        }
        let result = try ManualStubBatchGenerator(
            sources: sources,
            additionalImports: additionalImports
        ).render()
        output = result.source
        for skipped in result.skippedProtocols {
            writeError(
                "ManualStubGeneratorTool: skipped \(skipped.name) in "
                    + "\(skipped.sourceIdentifier): \(skipped.reason)"
            )
        }
    } else {
        let source = try String(contentsOf: inputURL, encoding: .utf8)
        guard moduleSources.isEmpty else {
            throw ToolError.moduleSourceRequiresBatchGeneration
        }
        output = try ManualStubGenerator(
            protocolName: selection,
            source: source
        ).render(additionalImports: additionalImports)
    }
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    // A build-tool plugin sandbox grants write access to its declared output,
    // not to the sibling temporary file Foundation creates for an atomic
    // write. A failed command is rerun by the build system, so write the
    // generated output directly instead.
    try output.write(to: outputURL, atomically: false, encoding: .utf8)
} catch {
    writeError("ManualStubGeneratorTool: \(error.localizedDescription)")
    exit(1)
}

func sourceFiles(at inputURL: URL, excluding outputURL: URL) throws -> [URL] {
    var isDirectory: ObjCBool = false
    guard
        FileManager.default.fileExists(
            atPath: inputURL.path,
            isDirectory: &isDirectory
        )
    else {
        throw CocoaError(.fileNoSuchFile)
    }
    if isDirectory.boolValue == false {
        return [inputURL]
    }

    let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
    guard
        let enumerator = FileManager.default.enumerator(
            at: inputURL,
            includingPropertiesForKeys: resourceKeys
        )
    else {
        throw ToolError.cannotEnumerateDirectory(inputURL.path)
    }
    return try enumerator.compactMap { element -> URL? in
        guard let url = element as? URL,
            url.pathExtension == "swift",
            url.standardizedFileURL != outputURL,
            try url.resourceValues(forKeys: Set(resourceKeys)).isRegularFile == true
        else {
            return nil
        }
        return url.standardizedFileURL
    }.sorted { $0.path < $1.path }
}

enum ToolError: LocalizedError {
    case outputOverwritesInput
    case cannotEnumerateDirectory(String)
    case moduleSourceRequiresBatchGeneration

    var errorDescription: String? {
        switch self {
            case .outputOverwritesInput:
                "the batch output must not overwrite its input source file"
            case .cannotEnumerateDirectory(let path):
                "could not enumerate source directory \(path)"
            case .moduleSourceRequiresBatchGeneration:
                "--module-source requires --all"
        }
    }
}
