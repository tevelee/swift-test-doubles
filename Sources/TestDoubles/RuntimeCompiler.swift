import Foundation
import Echo

// ============================================================================
// Runtime Compiler — generates and compiles mock conforming types at test time
//
// Flow:
// 1. Discover protocol requirements via Echo + dladdr
// 2. Generate Swift source for a conforming type that dispatches to MockBridge
// 3. Compile to dylib with swiftc
// 4. dlopen the result
// 5. Find the conformance via Echo
// 6. Return the witness table for use in RuntimeStub
// ============================================================================

/// Cache of compiled mock dylibs to avoid recompilation.
nonisolated(unsafe) private var _compiledCache: [String: UnsafeRawPointer] = [:]

public enum RuntimeCompiler {

    /// Compile a mock type for the given protocol and return the dylib path.
    /// Returns nil if compilation fails.
    static func compileMock(
        protocolName: String,
        moduleName: String,
        signatures: [DiscoveredSignature]
    ) -> String? {
        let cacheKey = "\(moduleName).\(protocolName)"

        let source = generateSource(
            protocolName: protocolName,
            moduleName: moduleName,
            signatures: signatures
        )

        guard let dylibPath = compile(source: source, key: cacheKey) else {
            return nil
        }

        guard dlopen(dylibPath, RTLD_NOW) != nil else {
            print("[RuntimeCompiler] dlopen failed: \(String(cString: dlerror()))")
            return nil
        }

        return dylibPath
    }

    /// Extract the module name from a demangled witness string.
    /// e.g. "protocol witness for MyModule.MyService.load(...) in conformance MyModule.RealService : MyModule.MyService"
    /// → "MyModule"
    static func extractModuleName(from demangled: String) -> String? {
        // Pattern: "in conformance ModuleName.TypeName : ModuleName.ProtocolName"
        guard let confRange = demangled.range(of: " in conformance ") else { return nil }
        let afterConf = String(demangled[confRange.upperBound...])
        // First component before "." is the module name
        let parts = afterConf.components(separatedBy: ".")
        return parts.first
    }

    // MARK: - Source Generation

    static func generateSource(
        protocolName: String,
        moduleName: String,
        signatures: [DiscoveredSignature]
    ) -> String {
        let imports = moduleName == "TestDoubles"
            ? "import TestDoubles"
            : "import TestDoubles\nimport \(moduleName)"

        let mockableSignatures = signatures.filter { sig in
            switch sig.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return false
            default:
                return true
            }
        }

        let members = mockableSignatures.map { generateMember($0) }.joined(separator: "\n")

        return """
        \(imports)

        public struct _TDMock: \(protocolName) {
            public let _ctx: UnsafeRawPointer
            public init(_ctx: UnsafeRawPointer) { self._ctx = _ctx }

        \(members)
        }
        """
    }

    private static func generateMember(_ sig: DiscoveredSignature) -> String {
        switch sig.kind {
        case .getter:
            let ret: String = sig.ret
            return "    public var \(sig.methodName): \(ret) { MockBridge.dispatch(_ctx, slot: \(sig.slot)) }"
        case .setter:
            return "    // setter for \(sig.methodName) — handled by modify coroutine"
        case .method:
            return generateMethod(sig)
        default:
            return "    // unsupported: \(sig.kind)"
        }
    }

    private static func generateMethod(_ sig: DiscoveredSignature) -> String {
        let name = sig.methodName.components(separatedBy: "(").first ?? sig.methodName
        let asyncKw = sig.isAsync ? "async " : ""
        let throwsKw = sig.isThrowing ? "throws " : ""
        let bridgePrefix = sig.isThrowing ? "try MockBridge.throwingDispatch" : "MockBridge.dispatch"
        let bridgeVoidPrefix = sig.isThrowing ? "try MockBridge.throwingDispatchVoid" : "MockBridge.dispatchVoid"

        let params = sig.args.enumerated().map { i, type in
            let label = i < sig.paramLabels.count ? sig.paramLabels[i] : "_"
            return "\(label) arg\(i): \(type)"
        }.joined(separator: ", ")

        let argList = sig.args.isEmpty ? "" : sig.args.enumerated()
            .map { "arg\($0.offset)" }.joined(separator: ", ")
        let argsExpr = sig.args.isEmpty ? "[]" : "[\(argList)]"

        if sig.ret == "Void" {
            return "    public func \(name)(\(params)) \(asyncKw)\(throwsKw){ \(bridgeVoidPrefix)(_ctx, slot: \(sig.slot), args: \(argsExpr)) }"
        }

        return "    public func \(name)(\(params)) \(asyncKw)\(throwsKw)-> \(sig.ret) { \(bridgePrefix)(_ctx, slot: \(sig.slot), args: \(argsExpr)) }"
    }

    // MARK: - Compilation

    // MARK: - Compilation

    /// Additional module search paths for the compiler.
    /// Set this before creating stubs if your protocol is in a custom framework.
    /// Enable/disable runtime compilation.
    /// Set to `true` to enable automatic compilation of mock types for
    /// throwing/async protocols. Requires swiftc on PATH.
    nonisolated(unsafe) public static var isEnabled = false

    nonisolated(unsafe) public static var additionalImportPaths: [String] = []
    nonisolated(unsafe) public static var additionalLibraryPaths: [String] = []
    nonisolated(unsafe) public static var additionalFrameworkPaths: [String] = []

    private static func compile(source: String, key: String) -> String? {
        let tmpDir = NSTemporaryDirectory()
        let hash = abs(key.hashValue)
        let srcPath = "\(tmpDir)td_mock_\(hash).swift"
        let dylibPath = "\(tmpDir)td_mock_\(hash).dylib"

        // Check cache
        if FileManager.default.fileExists(atPath: dylibPath) {
            return dylibPath
        }

        try? source.write(toFile: srcPath, atomically: true, encoding: .utf8)

        // Find SDK path
        let sdkPath = Self.findSDKPath()

        // Find swiftc
        let swiftc = Self.findSwiftc()

        var args = [
            "-emit-library",
            "-module-name", "TDMockGen",
            "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
            "-o", dylibPath,
        ]

        // SDK
        if let sdk = sdkPath {
            args += ["-sdk", sdk]
        }

        // Auto-detect module search paths from the running binary
        let autoImportPaths = Self.detectImportPaths()
        for path in autoImportPaths + additionalImportPaths {
            args += ["-I", path]
        }
        for path in autoImportPaths + additionalLibraryPaths {
            args += ["-L", path]
        }
        for path in additionalFrameworkPaths {
            args += ["-F", path]
        }

        args.append(srcPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftc)
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                print("[RuntimeCompiler] Compilation failed:\n\(stderr)")
                print("[RuntimeCompiler] Source: \(srcPath)")
                return nil
            }

            return dylibPath
        } catch {
            print("[RuntimeCompiler] Process error: \(error)")
            return nil
        }
    }

    /// Auto-detect module import paths from the running binary's location.
    /// For SPM builds, modules are in .build/<arch>/debug/Modules.
    private static func detectImportPaths() -> [String] {
        var paths: [String] = []

        // Try to find .build directory by walking up from the executable
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        var dir = execURL.deletingLastPathComponent()

        // Walk up looking for a directory containing Modules/
        for _ in 0..<10 {
            let modulesDir = dir.appendingPathComponent("Modules")
            if FileManager.default.fileExists(atPath: modulesDir.path) {
                paths.append(modulesDir.path)
                paths.append(dir.path) // for -L (library search)
                break
            }
            dir = dir.deletingLastPathComponent()
        }

        // Also check standard SPM build paths relative to current working directory
        let cwd = FileManager.default.currentDirectoryPath
        for buildDir in [
            "\(cwd)/.build/arm64-apple-macosx/debug",
            "\(cwd)/.build/debug",
        ] {
            let modulesPath = "\(buildDir)/Modules"
            if FileManager.default.fileExists(atPath: modulesPath) {
                paths.append(modulesPath)
                paths.append(buildDir)
            }
        }

        return Array(Set(paths)) // deduplicate
    }

    private static func findSDKPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findSwiftc() -> String {
        // Prefer the swiftc from PATH (matches the toolchain that built the module)
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["swiftc"]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()
        if whichProcess.terminationStatus == 0 {
            let path = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let p = path, !p.isEmpty { return p }
        }

        // Fallback to xcrun
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "swiftc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/usr/bin/swiftc"
    }
}

