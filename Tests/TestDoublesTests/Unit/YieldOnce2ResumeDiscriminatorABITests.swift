import Foundation
import Testing

@testable import TestDoubles

#if canImport(Darwin)

/// Cross-checks `YieldingAccessorRuntime.resumeDiscriminator` -- the exact
/// function the trampoline calls when fabricating a Swift 6.3 `yield_once_2`
/// read/modify witness veneer -- against a live Swift 6.3 compiler's own
/// arm64e resume-discriminator codegen, for several distinct yield shapes.
///
/// An earlier revision of Scripts/check-swift-abi-constants.sh instead
/// hand-copied the discriminator's spelling algorithm into a small C probe.
/// That reproduction could only ever catch a divergence between two
/// hand-written copies, not a bug in the real Swift source of
/// `pointerAuthTypeSpelling` / `resumeDiscriminator` itself. Calling the
/// actual shipped function here, `@testable`, means a mismatch is a genuine
/// finding about the library.
@Suite(.enabled(if: liveSwift63CompilerIsAvailable))
private struct YieldOnce2ResumeDiscriminatorABITests {
    @Test(arguments: YieldOnce2ResumeDiscriminatorProbe.all)
    func libraryDiscriminatorMatchesTheLiveCompiler(
        _ probe: YieldOnce2ResumeDiscriminatorProbe
    ) throws {
        let compilerDiscriminator = try probe.compilerDerivedResumeDiscriminator()
        let libraryDiscriminator = YieldingAccessorRuntime.resumeDiscriminator(
            isIndirect: probe.isIndirect,
            returnType: probe.returnType
        )
        #expect(
            libraryDiscriminator == compilerDiscriminator,
            """
            \(probe.name): library computed \(libraryDiscriminator.map(String.init) ?? "nil"), \
            live Swift 6.3 compiler emitted \(compilerDiscriminator).
            """
        )
    }
}

/// A real class type usable as a `returnType`. Only its metadata *kind*
/// matters to `pointerAuthTypeSpelling` (the `-class` spelling is a constant,
/// independent of the class's identity), so nothing else about this type is
/// significant.
private final class YieldOnce2ResumeDiscriminatorProbeReferenceType {
    init() {}
}

/// One yield shape exercising a distinct branch of
/// `pointerAuthTypeSpelling` / `YieldingAccessorRuntime.resumeDiscriminator`.
private struct YieldOnce2ResumeDiscriminatorProbe: Sendable, CustomStringConvertible {
    let name: String
    /// Passed to the real, shipped `YieldingAccessorRuntime.resumeDiscriminator`.
    /// Unread when `isIndirect` is true (that branch never reaches
    /// `pointerAuthTypeSpelling`), so a probe that only exercises the
    /// indirect branch may use any placeholder type here.
    let returnType: Any.Type
    let isIndirect: Bool
    fileprivate let probeID: String
    fileprivate let typeSpelling: String
    fileprivate let auxiliaryDeclaration: String

    var description: String { name }

    static let all: [YieldOnce2ResumeDiscriminatorProbe] = [
        YieldOnce2ResumeDiscriminatorProbe(
            name: "Int (direct scalar, non-generic struct mangled-name branch)",
            returnType: Int.self,
            isIndirect: false,
            probeID: "Int",
            typeSpelling: "Int",
            auxiliaryDeclaration: ""
        ),
        YieldOnce2ResumeDiscriminatorProbe(
            name: "Bool (direct scalar, distinct non-generic struct mangled name)",
            returnType: Bool.self,
            isIndirect: false,
            probeID: "Bool",
            typeSpelling: "Bool",
            auxiliaryDeclaration: ""
        ),
        YieldOnce2ResumeDiscriminatorProbe(
            name: "class reference (direct, constant \"-class\" spelling)",
            returnType: YieldOnce2ResumeDiscriminatorProbeReferenceType.self,
            isIndirect: false,
            probeID: "Class",
            typeSpelling: "ProbeReferenceType",
            auxiliaryDeclaration: """
                public final class ProbeReferenceType {
                  public init() {}
                }
                """
        ),
        YieldOnce2ResumeDiscriminatorProbe(
            name: "64-byte struct (formally indirect result, bypasses pointerAuthTypeSpelling)",
            returnType: Int.self,
            isIndirect: true,
            probeID: "Indirect",
            typeSpelling: "ProbeLargeStruct",
            auxiliaryDeclaration: """
                public struct ProbeLargeStruct {
                  public var a = 0
                  public var b = 0
                  public var c = 0
                  public var d = 0
                  public var e = 0
                  public var f = 0
                  public var g = 0
                  public var h = 0
                  public init() {}
                }
                """
        ),
    ]

    /// Compiles a minimal Swift 6.3 `read` accessor yielding this probe's
    /// type, asks a live `xcrun swiftc` for its arm64e assembly, and extracts
    /// the resume-authentication discriminator the compiler embedded --
    /// mirroring `compile_swift_63_read_probe` in
    /// Scripts/check-swift-abi-constants.sh.
    func compilerDerivedResumeDiscriminator() throws -> UInt16 {
        let moduleName = "TDResumeDiscriminatorProbe\(probeID)"
        let source = """
            \(auxiliaryDeclaration)

            public protocol \(moduleName)Protocol {
              var value: \(typeSpelling) { read }
            }

            public struct \(moduleName)Conformer: \(moduleName)Protocol {
              private var storage: \(typeSpelling)

              public init(storage: \(typeSpelling)) {
                self.storage = storage
              }

              public var value: \(typeSpelling) {
                read { yield storage }
              }
            }
            """

        let assembly = try Self.runXcrunSwiftc(
            arguments: [
                "swiftc",
                "-emit-assembly",
                "-parse-as-library",
                "-enable-experimental-feature", "CoroutineAccessors",
                "-module-name", moduleName,
                "-target", "arm64e-apple-macosx13.0",
                "-o", "-",
                "-",
            ],
            standardInput: source
        )
        guard let discriminator = Self.extractARM64EResumeDiscriminator(fromAssembly: assembly)
        else {
            throw ProbeError(
                message:
                    "\(name): could not find the arm64e resume-discriminator codegen pattern "
                    + "(mov x17, x0 / movk x17, #N, lsl #48 / pacia x16, x17) in the compiler's assembly."
            )
        }
        return discriminator
    }

    /// Reproduces the three-instruction pattern
    /// Scripts/check-swift-abi-constants.sh scans for with `awk`: the
    /// discriminator the compiler blends into `x17` immediately before
    /// signing a resume function pointer with `pacia x16, x17`.
    private static func extractARM64EResumeDiscriminator(
        fromAssembly assembly: String
    ) -> UInt16? {
        let selfMove = /mov\s+x17,\s*x0/
        let movk = /movk\s+x17,\s*#(\d+),\s*lsl\s*#48/
        let pacia = /pacia\s+x16,\s*x17/

        var candidate: UInt16?
        var candidateLineIndex = -1
        for (index, line) in assembly.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.firstMatch(of: selfMove) != nil {
                candidateLineIndex = index
                continue
            }
            if index == candidateLineIndex + 1, let match = line.firstMatch(of: movk) {
                candidate = UInt16(match.output.1)
                candidateLineIndex = index
                continue
            }
            if index == candidateLineIndex + 1, line.firstMatch(of: pacia) != nil {
                return candidate
            }
        }
        return nil
    }

    private static func runXcrunSwiftc(
        arguments: [String],
        standardInput: String
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        stdinPipe.fileHandleForWriting.write(Data(standardInput.utf8))
        try stdinPipe.fileHandleForWriting.close()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            throw ProbeError(
                message:
                    "xcrun \(arguments.joined(separator: " ")) exited \(process.terminationStatus): "
                    + String(decoding: errorData, as: UTF8.self)
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

private struct ProbeError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Gates the whole suite on a live, exact Swift 6.3 `xcrun swiftc`, mirroring
/// Scripts/check-swift-abi-constants.sh's own version check. Off that exact
/// toolchain -- including entirely off Apple platforms, where `xcrun` does
/// not exist -- the suite is skipped rather than failing.
private let liveSwift63CompilerIsAvailable: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swiftc", "--version"]
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    guard (try? process.run()) != nil else { return false }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return false }
    return String(decoding: data, as: UTF8.self).contains("Apple Swift version 6.3")
}()

#endif
