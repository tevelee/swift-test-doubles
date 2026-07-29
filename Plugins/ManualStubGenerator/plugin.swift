import Foundation
import PackagePlugin

@main
struct ManualStubGeneratorPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        guard arguments.count == 3 else {
            throw GeneratorError.usage
        }
        let tool = try context.tool(named: "ManualStubGeneratorTool")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.url.path())
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GeneratorError.failed
        }
    }
}

private enum GeneratorError: LocalizedError {
    case usage
    case failed

    var errorDescription: String? {
        switch self {
            case .usage:
                """
                usage:
                  swift package plugin --allow-writing-to-package-directory generate-manual-stub <ProtocolName> <source.swift> <output.swift>
                  swift package plugin --allow-writing-to-package-directory generate-manual-stub --all <source.swift-or-directory> <output.swift>
                """
            case .failed:
                "ManualStub generation failed."
        }
    }
}
