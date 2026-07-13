#if COMPILED_STUB && os(macOS)
import Darwin
import Foundation

/// Compiles and loads Swift dynamic-replacement images.
///
/// This is useful when the implementation module is built with
/// `-Xfrontend -enable-implicit-dynamic`; a loaded replacement image can then
/// provide `@_dynamicReplacement` declarations for concrete functions and
/// methods, not just protocol witnesses.
public enum DynamicReplacementCompiler {
    public struct CompiledModule: Sendable {
        public let moduleName: String
        public let directory: String
        public let libraryPath: String
        public let modulePath: String
    }

    public struct Failure: Error, Sendable, CustomStringConvertible {
        public let reason: String
        public let stderr: String
        public let sourcePath: String
        public let arguments: [String]

        public var description: String {
            var lines = [reason, "source: \(sourcePath)"]
            if arguments.isEmpty == false {
                lines.append("arguments: \(arguments.joined(separator: " "))")
            }
            if stderr.isEmpty == false {
                lines.append("stderr:\n\(stderr)")
            }
            return lines.joined(separator: "\n")
        }
    }

    public static func compileDynamicModule(
        moduleName: String,
        source: String,
        importPaths: [String] = []
    ) throws -> CompiledModule {
        let directory = cacheDirectory(key: "subject|\(moduleName)|\(source)|\(importPaths.joined(separator: ":"))")
        let sourcePath = "\(directory)/\(moduleName).swift"
        let libraryPath = "\(directory)/lib\(moduleName).dylib"
        let modulePath = "\(directory)/\(moduleName).swiftmodule"

        try write(source, to: sourcePath)
        var arguments = [
            "-emit-library",
            "-emit-module",
            "-module-name", moduleName,
            "-Xfrontend", "-enable-implicit-dynamic",
            "-emit-module-path", modulePath,
            "-o", libraryPath,
        ]
        arguments += sdkArguments()
        for path in importPaths {
            arguments += ["-I", path]
        }
        arguments.append(sourcePath)

        try runSwiftc(arguments, sourcePath: sourcePath)
        return CompiledModule(
            moduleName: moduleName,
            directory: directory,
            libraryPath: libraryPath,
            modulePath: modulePath
        )
    }

    @discardableResult
    public static func loadReplacement(
        moduleName: String,
        source: String,
        importPaths: [String],
        libraryPaths: [String] = [],
        linkedLibraries: [String] = []
    ) throws -> UnsafeMutableRawPointer {
        let key = [
            "replacement",
            moduleName,
            source,
            importPaths.joined(separator: ":"),
            libraryPaths.joined(separator: ":"),
            linkedLibraries.joined(separator: ":"),
        ].joined(separator: "|")
        let directory = cacheDirectory(key: key)
        let sourcePath = "\(directory)/\(moduleName).swift"
        let libraryPath = "\(directory)/lib\(moduleName).dylib"

        try write(source, to: sourcePath)
        var arguments = [
            "-emit-library",
            "-module-name", moduleName,
            "-Xlinker", "-undefined",
            "-Xlinker", "dynamic_lookup",
            "-o", libraryPath,
        ]
        arguments += sdkArguments()
        for path in importPaths {
            arguments += ["-I", path]
        }
        for path in libraryPaths {
            arguments += ["-L", path, "-Xlinker", "-rpath", "-Xlinker", path]
        }
        for library in linkedLibraries {
            arguments.append("-l\(library)")
        }
        arguments.append(sourcePath)

        try runSwiftc(arguments, sourcePath: sourcePath)
        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_GLOBAL) else {
            throw Failure(
                reason: "dlopen failed: \(String(cString: dlerror()))",
                stderr: "",
                sourcePath: sourcePath,
                arguments: arguments
            )
        }
        return handle
    }

    private static func cacheDirectory(key: String) -> String {
        let hash = key.utf8.reduce(into: UInt64(5381)) { h, c in
            h = h &* 33 &+ UInt64(c)
        }
        let directory = NSTemporaryDirectory() + "swift-test-doubles/dynamic-replacements/\(hash)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ source: String, to path: String) throws {
        do {
            try source.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw Failure(reason: "Failed to write source: \(error)", stderr: "", sourcePath: path, arguments: [])
        }
    }

    private static func runSwiftc(_ arguments: [String], sourcePath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath("swiftc"))
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(
                reason: "swiftc failed",
                stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                sourcePath: sourcePath,
                arguments: arguments
            )
        }
    }

    private static func sdkArguments() -> [String] {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
            return []
        }
        let result = run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"])
        let sdk = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && sdk.isEmpty == false ? ["-sdk", sdk] : []
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
}

private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}
#endif
