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

    public struct Failure: Sendable, CustomStringConvertible {
        public let reason: String
        public let stderr: String
        public let sourcePath: String?
        public let swiftcPath: String?
        public let arguments: [String]

        public var description: String {
            var lines = [reason]
            if let swiftcPath { lines.append("swiftc: \(swiftcPath)") }
            if !arguments.isEmpty { lines.append("arguments: \(arguments.joined(separator: " "))") }
            if let sourcePath { lines.append("source: \(sourcePath)") }
            if !stderr.isEmpty { lines.append("stderr:\n\(stderr)") }
            return lines.joined(separator: "\n")
        }
    }

    nonisolated(unsafe) public private(set) static var lastFailure: Failure?

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
            let message = "dlopen failed: \(String(cString: dlerror()))"
            lastFailure = Failure(reason: message, stderr: "", sourcePath: dylibPath, swiftcPath: nil, arguments: [])
            print("[RuntimeCompiler] \(message)")
            return nil
        }
        lastFailure = nil
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

        @_cdecl("swift_mock_witness_table")
        public func _swift_mock_witness_table() -> UnsafeRawPointer {
            var mock: any \(protocolName) = _TDMock(_ctx: UnsafeRawPointer(bitPattern: 1)!)
            return withUnsafePointer(to: &mock) { ptr in
                (UnsafeRawPointer(ptr) + 4 * MemoryLayout<UnsafeRawPointer>.size)
                    .load(as: UnsafeRawPointer.self)
            }
        }

        @_cdecl("swift_mock_type_metadata")
        public func _swift_mock_type_metadata() -> UnsafeRawPointer {
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
        let importPaths = detectImportPaths()
        let swiftcPath = findSwiftc(importPaths: importPaths)
        // Prefer the SDK from the Xcode that owns swiftcPath so it matches the SDK
        // used to build TestDoubles.swiftmodule. Fall back to SDKROOT, then xcrun.
        let sdkFromSwiftc = sdkPath(forSwiftcPath: swiftcPath)
        let sdkFromEnv = ProcessInfo.processInfo.environment["SDKROOT"]
        let sdkFromXcrun = sdkFromSwiftc == nil && sdkFromEnv == nil
            ? shell("/usr/bin/xcrun", "--show-sdk-path") : nil
        let sdk = sdkFromSwiftc ?? sdkFromEnv ?? sdkFromXcrun ?? ""
        let sdkDir = sdkCacheLabel(sdk)
        let cacheKey = "\(key)|\(swiftcPath)|\(sdk)|\(source)"
        let hash = cacheKey.utf8.reduce(into: UInt64(5381)) { h, c in h = h &* 33 &+ UInt64(c) }
        let cacheDir = NSTemporaryDirectory() + "swift-test-doubles/\(sdkDir)/"
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let srcPath = "\(cacheDir)swift_mock_\(hash).swift"
        let dylibPath = "\(cacheDir)swift_mock_\(hash).dylib"

        compileLock.lock()
        defer { compileLock.unlock() }

        if FileManager.default.fileExists(atPath: dylibPath) { return dylibPath }

        do {
            try source.write(toFile: srcPath, atomically: true, encoding: .utf8)
        } catch {
            lastFailure = Failure(
                reason: "Failed to write mock source to \(srcPath): \(error)",
                stderr: "",
                sourcePath: srcPath,
                swiftcPath: swiftcPath,
                arguments: []
            )
            return nil
        }

        var args = ["-emit-library", "-module-name", "TDMockGen",
                    "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
                    "-o", dylibPath]

        if !sdk.isEmpty {
            args += ["-sdk", sdk]
        }
        for path in importPaths + additionalImportPaths { args += ["-I", path] }
        for path in importPaths + additionalLibraryPaths { args += ["-L", path] }
        for path in detectPlatformFrameworkPaths(swiftcPath: swiftcPath) + additionalFrameworkPaths { args += ["-F", path] }
        for mapFile in detectGeneratedModuleMapFiles(importPaths: importPaths) { args += ["-Xcc", "-fmodule-map-file=\(mapFile)"] }
        args.append(srcPath)

        let (process, errPipe) = makeSwiftcProcess(swiftcPath: swiftcPath, args: args)

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                // SDK mismatch: find the SDK the module was built with and retry once.
                if let requiredCanonicalName = stderr
                    .components(separatedBy: "built with SDK '").dropFirst().first?
                    .components(separatedBy: "'").first,
                   let matchingSDK = findSDKByCanonicalName(requiredCanonicalName),
                   matchingSDK != sdk {

                    print("[RuntimeCompiler] SDK mismatch (\(sdk.isEmpty ? "none" : URL(fileURLWithPath: sdk).lastPathComponent) ≠ \(requiredCanonicalName)), retrying with \(URL(fileURLWithPath: matchingSDK).lastPathComponent)")

                    var retryArgs = args
                    if let sdkIdx = retryArgs.firstIndex(of: "-sdk"), sdkIdx + 1 < retryArgs.count {
                        retryArgs[sdkIdx + 1] = matchingSDK
                    } else {
                        retryArgs.insert(contentsOf: ["-sdk", matchingSDK], at: 0)
                    }
                    let retryCacheDir = NSTemporaryDirectory() + "swift-test-doubles/\(sdkCacheLabel(matchingSDK))/"
                    try? FileManager.default.createDirectory(atPath: retryCacheDir, withIntermediateDirectories: true)
                    let retryDylibPath = "\(retryCacheDir)swift_mock_\(hash).dylib"
                    if let idx = retryArgs.firstIndex(of: dylibPath) { retryArgs[idx] = retryDylibPath }

                    let (retryProcess, retryErrPipe) = makeSwiftcProcess(swiftcPath: swiftcPath, args: retryArgs)
                    if (try? retryProcess.run()) != nil {
                        retryProcess.waitUntilExit()
                        if retryProcess.terminationStatus == 0 {
                            lastFailure = nil
                            return retryDylibPath
                        }
                        let retryStderr = String(data: retryErrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        print("[RuntimeCompiler] Retry also failed:\n\(retryStderr)")
                    }
                }

                var reason = "Compilation failed"
                if stderr.contains("cannot load module") && stderr.contains("built with SDK") && stderr.contains("when using SDK") {
                    let builtWith = stderr.components(separatedBy: "built with SDK '").dropFirst().first?.components(separatedBy: "'").first
                    let usingSDK = stderr.components(separatedBy: "when using SDK '").dropFirst().first?.components(separatedBy: "'").first
                    let versions = [builtWith, usingSDK].compactMap { $0 }
                    let versionNote = versions.count == 2 ? " (module: \(versions[0]), compiler: \(versions[1]))" : ""
                    reason += "\nSDK mismatch\(versionNote): the module was compiled with a different SDK than the runtime compiler is using.\nFix: Clean Build Folder in Xcode (Product > Clean Build Folder), or run `swift package clean` in the terminal."
                }
                let env = ProcessInfo.processInfo.environment
                let diagnostics = """
                  swiftcPath:         \(swiftcPath)
                  sdkFromSwiftc:      \(sdkFromSwiftc ?? "nil")
                  sdkFromEnv(SDKROOT):\(sdkFromEnv ?? "nil")
                  sdkFromXcrun:       \(sdkFromXcrun ?? "nil (not tried)")
                  sdk (selected):     \(sdk.isEmpty ? "empty" : sdk)
                  DEVELOPER_DIR:      \(env["DEVELOPER_DIR"] ?? "nil")
                  DT_TOOLCHAIN_DIR:   \(env["DT_TOOLCHAIN_DIR"] ?? "nil")
                  BUILT_PRODUCTS_DIR: \(env["BUILT_PRODUCTS_DIR"] ?? "nil")
                  importPaths:        \(importPaths.joined(separator: "\n                        "))
                """
                lastFailure = Failure(reason: reason, stderr: stderr, sourcePath: srcPath, swiftcPath: swiftcPath, arguments: args)
                print("[RuntimeCompiler] Compilation failed:\n\(stderr)")
                print("[RuntimeCompiler] Diagnostics:\n\(diagnostics)")
                return nil
            }
            lastFailure = nil
            return dylibPath
        } catch {
            lastFailure = Failure(
                reason: "Process error: \(error)",
                stderr: "",
                sourcePath: srcPath,
                swiftcPath: swiftcPath,
                arguments: args
            )
            print("[RuntimeCompiler] Process error: \(error)")
            return nil
        }
    }

    // MARK: - Toolchain Discovery

    /// Find the swiftc whose version matches the one that built the module.
    private static func findSwiftc(importPaths: [String] = []) -> String {
        let buildVersion = detectBuildSwiftVersion()
        let environmentCandidates = preferredSwiftcCandidatesFromEnvironment()
        let xcrunSwiftc = shell("/usr/bin/xcrun", "--find", "swiftc")
        let shellSwiftc = shell("/usr/bin/which", "swiftc")
        let candidates = (environmentCandidates + [shellSwiftc, xcrunSwiftc].compactMap { $0 }).reduce(into: [String]()) { partial, candidate in
            guard !partial.contains(candidate) else { return }
            partial.append(candidate)
        }

        if importPaths.contains(where: { $0.contains("/Build/Products/") }) {
            return environmentCandidates.first
                ?? preferredXcodeSwiftcCandidate()
                ?? xcrunSwiftc
                ?? shellSwiftc
                ?? "/usr/bin/swiftc"
        }

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

    /// Auto-detect -F paths for platform developer frameworks (e.g. Testing.framework).
    private static func detectPlatformFrameworkPaths(swiftcPath: String) -> [String] {
        let env = ProcessInfo.processInfo.environment
        var paths: [String] = []

        for key in ["PLATFORM_DEVELOPER_FRAMEWORK_DIR", "DEVELOPER_FRAMEWORKS_DIR"] {
            if let path = env[key], FileManager.default.fileExists(atPath: path) {
                paths.append(path)
            }
        }

        if let developerDir = developerDirectory(forSwiftcPath: swiftcPath) {
            let derived = "\(developerDir)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
            if FileManager.default.fileExists(atPath: derived) {
                paths.append(derived)
            }
        }

        if paths.isEmpty,
           let platformPath = shell("/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path") {
            let derived = "\(platformPath)/Developer/Library/Frameworks"
            if FileManager.default.fileExists(atPath: derived) {
                paths.append(derived)
            }
        }

        return paths
    }

    /// Collect Xcode-generated module map files for C targets (e.g. _AtomicsShims).
    /// Xcode puts them in `Build/Intermediates.noindex/GeneratedModuleMaps/` as `*.modulemap`
    /// files — not `module.modulemap` — so they must be passed as `-Xcc -fmodule-map-file=`.
    private static func detectGeneratedModuleMapFiles(importPaths: [String]) -> [String] {
        var candidateProductDirs: [String] = []
        if let builtProductsDir = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            candidateProductDirs.append(builtProductsDir)
        }
        candidateProductDirs += importPaths

        for productDir in candidateProductDirs {
            // Navigate from .../Build/Products/Debug to .../Build/Intermediates.noindex/GeneratedModuleMaps
            let generatedModuleMapsDir = URL(fileURLWithPath: productDir)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Intermediates.noindex/GeneratedModuleMaps")
                .path
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: generatedModuleMapsDir) else {
                continue
            }
            let maps = entries
                .filter { $0.hasSuffix(".modulemap") }
                .map { "\(generatedModuleMapsDir)/\($0)" }
            if !maps.isEmpty { return maps }
        }
        return []
    }

    /// Find an SDK path whose canonical name matches (e.g. "macosx26.4" → MacOSX26.4.sdk).
    /// Prefers the versioned filename over unversioned aliases (e.g. MacOSX26.sdk) that share
    /// the same canonical name but may be missing modules like _AtomicsShims.
    private static func findSDKByCanonicalName(_ canonicalName: String) -> String? {
        var searchDirs: [String] = ["/Library/Developer/CommandLineTools/SDKs"]
        if let apps = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") {
            for app in apps.sorted().reversed() where app.hasPrefix("Xcode") && app.hasSuffix(".app") {
                searchDirs.append("/Applications/\(app)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs")
            }
        }

        // Pass 1: derive filename directly ("macosx26.4" → "MacOSX26.4.sdk")
        let versionedFilename = "MacOSX" + canonicalName.dropFirst("macosx".count) + ".sdk"
        for dir in searchDirs {
            let candidate = "\(dir)/\(versionedFilename)"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }

        // Pass 2: scan SDKSettings.json
        for dir in searchDirs {
            guard let sdks = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for sdk in sdks.sorted() where sdk.hasSuffix(".sdk") {
                let settingsPath = "\(dir)/\(sdk)/SDKSettings.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["CanonicalName"] as? String) == canonicalName else { continue }
                return "\(dir)/\(sdk)"
            }
        }
        return nil
    }

    /// Auto-detect -I/-L paths for the compiler.
    private static func detectImportPaths() -> [String] {
        var paths: [String] = []
        func appendUnique(_ path: String) {
            guard !paths.contains(path) else { return }
            paths.append(path)
        }
        func addCandidateDirectory(_ path: String) {
            guard FileManager.default.fileExists(atPath: path) else { return }

            if let entries = try? FileManager.default.contentsOfDirectory(atPath: path),
               entries.contains(where: { $0 == "Modules" || $0.hasSuffix(".swiftmodule") }) {
                appendUnique(path)
            }

            let modulesPath = "\(path)/Modules"
            if FileManager.default.fileExists(atPath: modulesPath) {
                appendUnique(modulesPath)
                appendUnique(path)
            }
        }

        for envKey in ["BUILT_PRODUCTS_DIR", "TARGET_BUILD_DIR", "CONFIGURATION_BUILD_DIR", "BUILD_DIR"] {
            if let dir = ProcessInfo.processInfo.environment[envKey] {
                addCandidateDirectory(dir)
            }
        }

        let executableDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
        for directory in ancestorDirectories(startingAt: executableDir, limit: 10) {
            addCandidateDirectory(directory.path)
        }

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            for directory in ancestorDirectories(startingAt: bundle.bundleURL.deletingLastPathComponent(), limit: 6) {
                addCandidateDirectory(directory.path)
            }
        }

        for buildDir in buildDirectories() {
            addCandidateDirectory(buildDir)
            // SPM C targets (e.g. _AtomicsShims) have module.modulemap in <Target>.build/
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: buildDir) {
                for entry in entries where entry.hasSuffix(".build") {
                    let dir = "\(buildDir)/\(entry)"
                    if FileManager.default.fileExists(atPath: "\(dir)/module.modulemap") {
                        appendUnique(dir)
                    }
                }
            }
        }

        return paths
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

    private static func preferredSwiftcCandidatesFromEnvironment() -> [String] {
        let env = ProcessInfo.processInfo.environment
        let rawCandidates = [
            env["SWIFT_EXEC"],
            env["TOOLCHAIN_DIR"].map { "\($0)/usr/bin/swiftc" },
            env["DT_TOOLCHAIN_DIR"].map { "\($0)/usr/bin/swiftc" },
            env["DEVELOPER_DIR"].map { "\($0)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" },
        ].compactMap { $0 }

        return rawCandidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func preferredXcodeSwiftcCandidate() -> String? {
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let candidates = entries
            .filter { $0.lastPathComponent.hasPrefix("Xcode") && $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for app in candidates {
            let swiftc = app
                .appendingPathComponent("Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
                .path
            if FileManager.default.isExecutableFile(atPath: swiftc) {
                return swiftc
            }
        }
        return nil
    }

    private static func developerDirectory(forSwiftcPath swiftcPath: String) -> String? {
        let marker = "/Contents/Developer/"
        guard let range = swiftcPath.range(of: marker) else { return nil }
        var path = String(swiftcPath[..<range.upperBound])
        if path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func sdkCacheLabel(_ sdkPath: String) -> String {
        let label = URL(fileURLWithPath: sdkPath).deletingPathExtension().lastPathComponent
            .lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." }
        return label.isEmpty ? "unknown" : label
    }

    private static func makeSwiftcProcess(swiftcPath: String, args: [String]) -> (Process, Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftcPath)
        process.arguments = args
        if let developerDir = developerDirectory(forSwiftcPath: swiftcPath) {
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["DEVELOPER_DIR": developerDir],
                uniquingKeysWith: { _, new in new }
            )
        }
        let errPipe = Pipe()
        process.standardError = errPipe
        return (process, errPipe)
    }

    private static func sdkPath(forSwiftcPath swiftcPath: String) -> String? {
        guard let developerDir = developerDirectory(forSwiftcPath: swiftcPath) else { return nil }
        // Pin DEVELOPER_DIR so xcrun resolves from this Xcode, not xcode-select (which may be CLT).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["--sdk", "macosx", "--show-sdk-path"]
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["DEVELOPER_DIR": developerDir],
            uniquingKeysWith: { _, new in new }
        )
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
