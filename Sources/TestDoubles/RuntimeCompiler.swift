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

    /// Compile a mock type and return the dlopen handle.
    /// Returns nil if compilation or loading fails.
    static func compileMock(
        protocolName: String,
        moduleName: String,
        signatures: [DiscoveredSignature]
    ) -> UnsafeMutableRawPointer? {
        let cacheKey = "\(moduleName).\(protocolName)"

        let source = generateSource(
            protocolName: protocolName,
            moduleName: moduleName,
            signatures: signatures
        )

        guard let dylibPath = compile(source: source, key: cacheKey) else {
            return nil
        }

        guard let handle = dlopen(dylibPath, RTLD_NOW) else {
            print("[RuntimeCompiler] dlopen failed: \(String(cString: dlerror()))")
            return nil
        }

        return handle
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

        // Self-describing accessors — called via dlsym after dlopen.
        // Avoids searching Echo's conformance tables (which crash on dynamic images).

        @_cdecl("td_mock_witness_table")
        public func _td_mock_witness_table() -> UnsafeRawPointer {
            var mock: any \(protocolName) = _TDMock(_ctx: UnsafeRawPointer(bitPattern: 1)!)
            return withUnsafePointer(to: &mock) { ptr in
                (UnsafeRawPointer(ptr) + 4 * MemoryLayout<UnsafeRawPointer>.size)
                    .load(as: UnsafeRawPointer.self)
            }
        }

        @_cdecl("td_mock_type_metadata")
        public func _td_mock_type_metadata() -> UnsafeRawPointer {
            unsafeBitCast(_TDMock.self as Any.Type, to: UnsafeRawPointer.self)
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

    /// Additional module search paths for the compiler.
    /// Set this before creating stubs if your protocol is in a custom framework.
    nonisolated(unsafe) public static var additionalImportPaths: [String] = []
    nonisolated(unsafe) public static var additionalLibraryPaths: [String] = []
    nonisolated(unsafe) public static var additionalFrameworkPaths: [String] = []

    /// Read the Swift version string from SPM's swift-version-*.txt file.
    /// Returns a short version like "6.2" or "6.3" for matching.
    private static func detectBuildSwiftVersion() -> String? {
        func findVersionFile(startingFrom dir: URL) -> String? {
            var dir = dir
            for _ in 0..<10 {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                    if let f = files.first(where: { $0.hasPrefix("swift-version-") && $0.hasSuffix(".txt") }) {
                        if let content = try? String(contentsOfFile: dir.appendingPathComponent(f).path, encoding: .utf8) {
                            let parts = content.split(separator: " ")
                            if let idx = parts.firstIndex(of: "version"), idx + 1 < parts.count {
                                return String(parts[idx + 1])
                            }
                        }
                    }
                }
                let prev = dir
                dir = dir.deletingLastPathComponent()
                if dir == prev { break }
            }
            return nil
        }

        // Try from executable path (works for direct SPM invocation)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        if let v = findVersionFile(startingFrom: execURL.deletingLastPathComponent()) { return v }

        // Try from CWD/.build (works for swiftpm-testing-helper and Xcode)
        let cwd = FileManager.default.currentDirectoryPath
        for buildDir in [
            "\(cwd)/.build/arm64-apple-macosx/debug",
            "\(cwd)/.build/arm64e-apple-macosx/debug",
            "\(cwd)/.build/debug",
        ] {
            if let v = findVersionFile(startingFrom: URL(fileURLWithPath: buildDir)) { return v }
        }
        return nil
    }

    private static let compileLock = NSLock()

    private static func compile(source: String, key: String) -> String? {
        // Stable hash (not randomized per process like .hashValue)
        let hash = key.utf8.reduce(into: UInt64(5381)) { h, c in
            h = h &* 33 &+ UInt64(c)
        }
        let tmpDir = NSTemporaryDirectory()
        let srcPath = "\(tmpDir)td_mock_\(hash).swift"
        let dylibPath = "\(tmpDir)td_mock_\(hash).dylib"

        compileLock.lock()
        defer { compileLock.unlock() }

        // Check cache (stable hash means this survives across test runs)
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
    private static func detectImportPaths() -> [String] {
        var paths: [String] = []
        let env = ProcessInfo.processInfo.environment

        // Xcode: BUILT_PRODUCTS_DIR contains compiled modules and libraries
        if let builtProducts = env["BUILT_PRODUCTS_DIR"] {
            paths.append(builtProducts)
            let modulesDir = "\(builtProducts)/Modules"
            if FileManager.default.fileExists(atPath: modulesDir) {
                paths.append(modulesDir)
            }
        }

        // SPM: walk up from executable to find Modules/
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

        // Include SPM-generated module maps for C targets (e.g. _AtomicsShims).
        // SPM generates module.modulemap inside .build/<arch>/debug/<Target>.build/
        for buildDir in [
            "\(cwd)/.build/arm64-apple-macosx/debug",
            "\(cwd)/.build/arm64e-apple-macosx/debug",
            "\(cwd)/.build/debug",
        ] {
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: buildDir) {
                for entry in entries where entry.hasSuffix(".build") {
                    let moduleMapDir = "\(buildDir)/\(entry)"
                    let moduleMap = "\(moduleMapDir)/module.modulemap"
                    if FileManager.default.fileExists(atPath: moduleMap) {
                        paths.append(moduleMapDir)
                    }
                }
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
        func run(_ exe: String, _ args: String...) -> String? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Read the Swift version that built the module from SPM's swift-version file.
        // Then match against candidate swiftc binaries.
        let buildVersion = Self.detectBuildSwiftVersion()

        let candidates: [String] = [
            run("/usr/bin/which", "swiftc"),
            run("/usr/bin/xcrun", "--find", "swiftc"),
        ].compactMap { $0 }.filter { !$0.isEmpty }

        if let buildVersion {
            for candidate in candidates {
                if let v = run(candidate, "--version"), v.contains(buildVersion) {
                    return candidate
                }
            }
        }

        // No version match — return first available
        return candidates.first ?? "/usr/bin/swiftc"
    }
}

