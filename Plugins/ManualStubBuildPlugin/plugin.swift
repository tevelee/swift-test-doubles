import Foundation
import PackagePlugin

@main
struct ManualStubBuildPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }
        let inputFiles = sourceTarget.sourceFiles(withSuffix: "swift")
            .map(\.url)
            .sorted { $0.path() < $1.path() }
        guard inputFiles.isEmpty == false else {
            return []
        }

        let tool = try context.tool(named: "ManualStubGeneratorTool")
        let output = context.pluginWorkDirectoryURL
            .appending(path: "GeneratedManualStubs.swift")
        return [
            .buildCommand(
                displayName: "Generating manual stubs for \(target.name)",
                executable: tool.url,
                arguments: [
                    "--all",
                    sourceTarget.directoryURL.path(),
                    output.path()
                ],
                inputFiles: inputFiles,
                outputFiles: [output]
            )
        ]
    }
}
