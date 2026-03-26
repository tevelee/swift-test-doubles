#if os(macOS)
import Foundation
import Echo

/// Compiles mock conforming types at test time via swiftc.
///
/// Flow: discover requirements → generate Swift source → compile to dylib → dlopen → extract witness table via dlsym.
public enum RuntimeCompiler {

    /// Additional search paths for the compiler.
    nonisolated(unsafe) public static var additionalImportPaths: [String] = []
    nonisolated(unsafe) public static var additionalLibraryPaths: [String] = []
    nonisolated(unsafe) public static var additionalFrameworkPaths: [String] = []

    // MARK: - Public

    /// Compile a mock type and return the dlopen handle, or nil on failure.
    static func compileMock(
        protocolName: String,
        moduleName: String,
        signatures: [DiscoveredSignature]
    ) -> UnsafeMutableRawPointer? {
        let source = generateSource(protocolName: protocolName, moduleName: moduleName, signatures: signatures)
        guard let dylibPath = compile(source: source, key: "\(moduleName).\(protocolName)") else { return nil }
        guard let handle = dlopen(dylibPath, RTLD_NOW) else {
            print("[RuntimeCompiler] dlopen failed: \(String(cString: dlerror()))")
            return nil
        }
        return handle
    }

    /// Extract the module name from a demangled witness string.
    static func extractModuleName(from demangled: String) -> String? {
        guard let range = demangled.range(of: " in conformance ") else { return nil }
        return String(demangled[range.upperBound...]).components(separatedBy: ".").first
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

        let members = signatures.compactMap { sig -> String? in
            switch sig.kind {
            case .getter:
                return "    public var \(sig.methodName): \(sig.ret) { MockBridge.dispatch(_ctx, slot: \(sig.slot)) }"
            case .method:
                return generateMethod(sig)
            case .modifyCoroutine, .readCoroutine, .setter,
                 .baseProtocol, .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return nil
            default:
                return nil
            }
        }.joined(separator: "\n")

        return """
        \(imports)

        public struct _TDMock: \(protocolName) {
            public let _ctx: UnsafeRawPointer
            public init(_ctx: UnsafeRawPointer) { self._ctx = _ctx }

        \(members)
        }

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

    private static func generateMethod(_ sig: DiscoveredSignature) -> String {
        let name = sig.methodName.components(separatedBy: "(").first ?? sig.methodName
        let asyncKw = sig.isAsync ? "async " : ""
        let throwsKw = sig.isThrowing ? "throws " : ""
        let isVoid = sig.ret == "Void"
        let bridge = sig.isThrowing
            ? (isVoid ? "try MockBridge.throwingDispatchVoid" : "try MockBridge.throwingDispatch")
            : (isVoid ? "MockBridge.dispatchVoid" : "MockBridge.dispatch")

        let params = sig.args.enumerated().map { i, type in
            let label = i < sig.paramLabels.count ? sig.paramLabels[i] : "_"
            return "\(label) arg\(i): \(type)"
        }.joined(separator: ", ")

        let argsExpr = sig.args.isEmpty ? "[]" : "[\(sig.args.indices.map { "arg\($0)" }.joined(separator: ", "))]"
        let call = "\(bridge)(_ctx, slot: \(sig.slot), args: \(argsExpr))"
        let arrow = isVoid ? "" : "-> \(sig.ret) "

        return "    public func \(name)(\(params)) \(asyncKw)\(throwsKw)\(arrow){ \(call) }"
    }

    // MARK: - Compilation

    private static let compileLock = NSLock()

    private static func compile(source: String, key: String) -> String? {
        let hash = key.utf8.reduce(into: UInt64(5381)) { h, c in h = h &* 33 &+ UInt64(c) }
        let tmpDir = NSTemporaryDirectory()
        let srcPath = "\(tmpDir)td_mock_\(hash).swift"
        let dylibPath = "\(tmpDir)td_mock_\(hash).dylib"

        compileLock.lock()
        defer { compileLock.unlock() }

        if FileManager.default.fileExists(atPath: dylibPath) { return dylibPath }

        try? source.write(toFile: srcPath, atomically: true, encoding: .utf8)

        var args = ["-emit-library", "-module-name", "TDMockGen",
                    "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
                    "-o", dylibPath]

        if let sdk = shell("/usr/bin/xcrun", "--show-sdk-path") { args += ["-sdk", sdk] }

        let importPaths = detectImportPaths()
        for path in importPaths + additionalImportPaths { args += ["-I", path] }
        for path in importPaths + additionalLibraryPaths { args += ["-L", path] }
        for path in additionalFrameworkPaths { args += ["-F", path] }
        args.append(srcPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: findSwiftc())
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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

    // MARK: - Toolchain Discovery

    /// Find the swiftc whose version matches the one that built the module.
    private static func findSwiftc() -> String {
        let buildVersion = detectBuildSwiftVersion()
        let candidates = [
            shell("/usr/bin/which", "swiftc"),
            shell("/usr/bin/xcrun", "--find", "swiftc"),
        ].compactMap { $0 }

        if let buildVersion {
            for candidate in candidates {
                if let v = shell(candidate, "--version"), v.contains(buildVersion) {
                    return candidate
                }
            }
        }
        return candidates.first ?? "/usr/bin/swiftc"
    }

    /// Read the Swift version (e.g. "6.3") from SPM's swift-version-*.txt.
    private static func detectBuildSwiftVersion() -> String? {
        let searchRoots = [
            URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
        ] + buildDirectories().map { URL(fileURLWithPath: $0) }

        for root in searchRoots {
            var dir = root
            for _ in 0..<10 {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
                   let file = files.first(where: { $0.hasPrefix("swift-version-") && $0.hasSuffix(".txt") }),
                   let content = try? String(contentsOfFile: dir.appendingPathComponent(file).path, encoding: .utf8) {
                    let parts = content.split(separator: " ")
                    if let i = parts.firstIndex(of: "version"), i + 1 < parts.count {
                        return String(parts[i + 1])
                    }
                }
                dir = dir.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// Auto-detect -I/-L paths for the compiler.
    private static func detectImportPaths() -> [String] {
        var paths: [String] = []

        // Xcode IDE: BUILT_PRODUCTS_DIR
        if let dir = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            paths.append(dir)
            paths.append("\(dir)/Modules")
        }

        // SPM: walk up from executable looking for Modules/
        var dir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
        for _ in 0..<10 {
            let modulesDir = dir.appendingPathComponent("Modules").path
            if FileManager.default.fileExists(atPath: modulesDir) {
                paths += [modulesDir, dir.path]
                break
            }
            dir = dir.deletingLastPathComponent()
        }

        // SPM build dirs (Modules + libraries + C target module maps)
        for buildDir in buildDirectories() {
            let modulesPath = "\(buildDir)/Modules"
            if FileManager.default.fileExists(atPath: modulesPath) {
                paths += [modulesPath, buildDir]
            }
            // C targets like _AtomicsShims have module.modulemap in <Target>.build/
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: buildDir) {
                for entry in entries where entry.hasSuffix(".build") {
                    let dir = "\(buildDir)/\(entry)"
                    if FileManager.default.fileExists(atPath: "\(dir)/module.modulemap") {
                        paths.append(dir)
                    }
                }
            }
        }

        return Array(Set(paths))
    }

    /// Standard SPM build directories relative to CWD.
    private static func buildDirectories() -> [String] {
        let cwd = FileManager.default.currentDirectoryPath
        return [
            "\(cwd)/.build/arm64-apple-macosx/debug",
            "\(cwd)/.build/arm64e-apple-macosx/debug",
            "\(cwd)/.build/debug",
        ]
    }

    /// Run a command, return trimmed stdout or nil.
    private static func shell(_ args: String...) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
