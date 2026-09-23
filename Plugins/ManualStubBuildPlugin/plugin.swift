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
        // Attached to a test target, the plugin also generates stubs for the
        // protocols its production dependencies in this package declare, so
        // those modules need no dependency on TestDoubles.
        let dependencies = sourceTarget.kind == .test ? dependencyModules(of: target) : []
        let inputFiles = ([sourceTarget] + dependencies)
            .flatMap { $0.sourceFiles(withSuffix: "swift").map(\.url) }
            .sorted { $0.path() < $1.path() }
        guard inputFiles.isEmpty == false else {
            return []
        }

        let tool = try context.tool(named: "ManualStubGeneratorTool")
        let output = context.pluginWorkDirectoryURL
            .appending(path: "GeneratedManualStubs.swift")
        let moduleArguments = dependencies.flatMap { dependency in
            ["--module-source", dependency.moduleName, dependency.directoryURL.path()]
        }
        return [
            .buildCommand(
                displayName: "Generating manual stubs for \(target.name)",
                executable: tool.url,
                arguments: [
                    "--all",
                    sourceTarget.directoryURL.path(),
                    output.path()
                ] + moduleArguments,
                inputFiles: inputFiles,
                outputFiles: [output]
            )
        ]
    }

    /// Swift library targets of this package that `target` depends on
    /// directly, excluding TestDoubles' own modules, which a client reaches
    /// as a product but this package's fixtures reach as targets.
    private func dependencyModules(of target: Target) -> [SwiftSourceModuleTarget] {
        let testDoublesModules: Set<String> = [
            "TestDoubles", "TestDoublesTesting", "TestDoublesMacros", "TestDoublesRuntime"
        ]
        return target.dependencies.compactMap { dependency in
            guard case .target(let dependencyTarget) = dependency,
                let module = dependencyTarget as? SwiftSourceModuleTarget,
                module.kind == .generic,
                testDoublesModules.contains(module.moduleName) == false
            else { return nil }
            return module
        }
    }
}
