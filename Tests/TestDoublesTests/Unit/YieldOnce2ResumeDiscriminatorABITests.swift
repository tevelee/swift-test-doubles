import Foundation
import Testing

@testable import TestDoubles

#if os(macOS)

    /// Cross-checks `YieldingAccessorRuntime`'s `readResumeDiscriminator(for:)`
    /// and `modifyResumeDiscriminator(for:)` -- the exact functions the
    /// trampoline calls when fabricating a Swift 6.3 `yield_once_2` read/modify
    /// witness veneer -- against a live Swift 6.3 compiler's own arm64e
    /// resume-discriminator codegen, for several distinct yield shapes and for
    /// both accessor kinds.
    ///
    /// An earlier revision of Scripts/check-swift-abi-constants.sh instead
    /// hand-copied the discriminator's spelling algorithm into a small C probe.
    /// That reproduction could only ever catch a divergence between two
    /// hand-written copies, not a bug in the real Swift source of
    /// `pointerAuthTypeSpelling` / `resumeDiscriminator` itself. Calling the
    /// actual shipped functions here, `@testable`, means a mismatch is a
    /// genuine finding about the library. Exactly that happened for `modify`:
    /// see the doc comment on `indirectYieldDiscriminatorIsAKnownOpenDiscrepancy`.
    @Suite(.enabled(if: liveSwift63CompilerIsAvailable))
    private struct YieldOnce2ResumeDiscriminatorABITests {
        @Test(arguments: YieldOnce2ResumeDiscriminatorProbe.all)
        func libraryDiscriminatorMatchesTheLiveCompiler(
            _ probe: YieldOnce2ResumeDiscriminatorProbe
        ) throws {
            try probe.assertLibraryDiscriminatorMatchesTheLiveCompiler()
        }

        /// `modify` always yields an address for in-place mutation, regardless
        /// of the property's value size, so `modifyResumeDiscriminator(for:)`
        /// unconditionally passes `isIndirect: true` -- unlike `read`, which
        /// only does so for results too large to return directly.
        /// `allModify`'s probes confirm the compiler agrees: a live Swift 6.3
        /// compiler emits the identical resume discriminator (`33953`) for the
        /// `modify` witness of an `Int`, a `Bool`, and a class reference,
        /// exactly the value it emits for a formally indirect `read`. These
        /// probes are tracked with `indirectYieldDiscriminatorIsAKnownOpenDiscrepancy`
        /// rather than asserted directly, because that shared indirect spelling
        /// is itself not yet reconciled with the library -- see that test's
        /// doc comment.
        @Test(arguments: YieldOnce2ResumeDiscriminatorProbe.allModify)
        func libraryDiscriminatorMatchesTheLiveCompilerForModify(
            _ probe: YieldOnce2ResumeDiscriminatorProbe
        ) throws {
            try withKnownIssue(
                """
                modifyResumeDiscriminator(for:)'s indirect-yield spelling has not been \
                reconciled with the live Swift 6.3 compiler; see the doc comment on \
                indirectYieldDiscriminatorIsAKnownOpenDiscrepancy.
                """
            ) {
                try probe.assertLibraryDiscriminatorMatchesTheLiveCompiler()
            }
        }

        /// The formally indirect yield path (`isIndirect: true`) is a genuinely
        /// open finding, not yet a confirmed library bug: a live Swift 6.3
        /// compiler's discriminator for a 64-byte struct's `read` accessor --
        /// and, as `libraryDiscriminatorMatchesTheLiveCompilerForModify` now
        /// also confirms, for *any* `modify` accessor regardless of type -- is
        /// `33953`, but the shared indirect-yield spelling this library computes
        /// (a bare `"indirect"`) hashes to `16775`. `"-indirect"` -- the
        /// leading-dash convention `pointerAuthFunctionSpelling` uses for an
        /// indirect *parameter* -- was the next most plausible guess and also
        /// does not match (`64687`). Both were checked by hashing candidate
        /// spellings directly with `td_function_discriminator`, not by asking a
        /// compiler, so this is not a search of the real IRGen source. Resolving
        /// this definitively needs either that source or a compiler transcript
        /// (`-emit-sil` / `-emit-ir`) for a `yield_once_2` witness with a
        /// genuinely indirect yield, neither of which was available while writing
        /// this test. Tracked here rather than guessed at, and rather than
        /// silently dropped: this branch had zero live-compiler coverage before
        /// this suite existed, and still has none that passes.
        @Test
        func indirectYieldDiscriminatorIsAKnownOpenDiscrepancy() throws {
            try withKnownIssue(
                """
                modifyResumeDiscriminator(for:)'s and readResumeDiscriminator(for:)'s shared \
                indirect-yield spelling has not been reconciled with the live Swift 6.3 compiler; \
                see the doc comment on this test.
                """
            ) {
                try YieldOnce2ResumeDiscriminatorProbe.indirectStruct
                    .assertLibraryDiscriminatorMatchesTheLiveCompiler()
            }
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
        /// Which `yield_once_2` witness kind to compile. `resumeDiscriminator`
        /// claims both share one spelling; `.modify` probes exist to check
        /// that claim rather than assume it.
        enum AccessorKind: Sendable {
            case read
            case modify
        }

        let name: String
        /// Passed to the real, shipped `YieldingAccessorRuntime.resumeDiscriminator`.
        /// Unread when `isIndirect` is true (that branch never reaches
        /// `pointerAuthTypeSpelling`), so a probe that only exercises the
        /// indirect branch may use any placeholder type here.
        let returnType: Any.Type
        let isIndirect: Bool
        let accessorKind: AccessorKind
        fileprivate let probeID: String
        fileprivate let typeSpelling: String
        fileprivate let auxiliaryDeclaration: String

        var description: String { name }

        /// Confirmed to match a live Swift 6.3 compiler.
        static let all: [YieldOnce2ResumeDiscriminatorProbe] = [
            YieldOnce2ResumeDiscriminatorProbe(
                name: "Int read (direct scalar, non-generic struct mangled-name branch)",
                returnType: Int.self,
                isIndirect: false,
                accessorKind: .read,
                probeID: "Int",
                typeSpelling: "Int",
                auxiliaryDeclaration: ""
            ),
            YieldOnce2ResumeDiscriminatorProbe(
                name: "Bool read (direct scalar, distinct non-generic struct mangled name)",
                returnType: Bool.self,
                isIndirect: false,
                accessorKind: .read,
                probeID: "Bool",
                typeSpelling: "Bool",
                auxiliaryDeclaration: ""
            ),
            YieldOnce2ResumeDiscriminatorProbe(
                name: "class reference read (direct, constant \"-class\" spelling)",
                returnType: YieldOnce2ResumeDiscriminatorProbeReferenceType.self,
                isIndirect: false,
                accessorKind: .read,
                probeID: "Class",
                typeSpelling: "ProbeReferenceType",
                auxiliaryDeclaration: """
                    public final class ProbeReferenceType {
                      public init() {}
                    }
                    """
            )
        ]

        /// The `modify` counterparts of the three confirmed `read` probes
        /// above. Unlike `read`, `modify` always yields indirectly regardless
        /// of the yielded type's value size, so every probe here uses
        /// `isIndirect: true` -- matching `modifyResumeDiscriminator(for:)`,
        /// which never consults `returnType`'s layout at all.
        static let allModify: [YieldOnce2ResumeDiscriminatorProbe] = [
            YieldOnce2ResumeDiscriminatorProbe(
                name: "Int modify (yield_once_2 modify witness, always indirect)",
                returnType: Int.self,
                isIndirect: true,
                accessorKind: .modify,
                probeID: "ModifyInt",
                typeSpelling: "Int",
                auxiliaryDeclaration: ""
            ),
            YieldOnce2ResumeDiscriminatorProbe(
                name: "Bool modify (yield_once_2 modify witness, always indirect)",
                returnType: Bool.self,
                isIndirect: true,
                accessorKind: .modify,
                probeID: "ModifyBool",
                typeSpelling: "Bool",
                auxiliaryDeclaration: ""
            ),
            YieldOnce2ResumeDiscriminatorProbe(
                name: "class reference modify (yield_once_2 modify witness, always indirect)",
                returnType: YieldOnce2ResumeDiscriminatorProbeReferenceType.self,
                isIndirect: true,
                accessorKind: .modify,
                probeID: "ModifyClass",
                typeSpelling: "ProbeReferenceType",
                auxiliaryDeclaration: """
                    public final class ProbeReferenceType {
                      public init() {}
                    }
                    """
            )
        ]

        /// Does NOT currently match a live Swift 6.3 compiler. See
        /// `indirectYieldDiscriminatorIsAKnownOpenDiscrepancy`.
        static let indirectStruct = YieldOnce2ResumeDiscriminatorProbe(
            name: "64-byte struct read (formally indirect result, bypasses pointerAuthTypeSpelling)",
            returnType: Int.self,
            isIndirect: true,
            accessorKind: .read,
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
        )

        /// Shared by both the confirmed-passing parameterized test and the
        /// tracked known-issue test, so both exercise the identical comparison.
        func assertLibraryDiscriminatorMatchesTheLiveCompiler() throws {
            let compilerDiscriminator = try compilerDerivedResumeDiscriminator()
            let libraryDiscriminator = YieldingAccessorRuntime.resumeDiscriminator(
                isIndirect: isIndirect,
                returnType: returnType
            )
            #expect(
                libraryDiscriminator == compilerDiscriminator,
                """
                \(name): library computed \(libraryDiscriminator.map(String.init) ?? "nil"), \
                live Swift 6.3 compiler emitted \(compilerDiscriminator).
                """
            )
        }

        /// Compiles a minimal Swift 6.3 `read` or `modify` accessor yielding
        /// this probe's type, asks a live `xcrun swiftc` for its arm64e
        /// assembly, and extracts the resume-authentication discriminator the
        /// compiler embedded -- mirroring `compile_swift_63_read_probe` /
        /// `compile_swift_63_modify_descriptor_probe` in
        /// Scripts/check-swift-abi-constants.sh.
        func compilerDerivedResumeDiscriminator() throws -> UInt16 {
            let moduleName = "TDResumeDiscriminatorProbe\(probeID)"
            let source: String
            switch accessorKind {
                case .read:
                    source = """
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
                case .modify:
                    // The conforming struct's own accessor must use the new
                    // `modify` keyword, not legacy `_modify`: the latter
                    // compiles to the ordinary yield_once convention (the
                    // fixed OpaqueModifyResumeFunction discriminator) for the
                    // struct's own accessor, which sits alongside -- and, as
                    // the first pacia site in the file, was mistaken by
                    // extractARM64EResumeDiscriminator for -- the protocol
                    // requirement's real yield_once_2 witness thunk discriminator.
                    source = """
                        \(auxiliaryDeclaration)

                        public protocol \(moduleName)Protocol {
                          var value: \(typeSpelling) { get set }
                        }

                        public struct \(moduleName)Conformer: \(moduleName)Protocol {
                          private var storage: \(typeSpelling)

                          public init(storage: \(typeSpelling)) {
                            self.storage = storage
                          }

                          public var value: \(typeSpelling) {
                            get { storage }
                            set { storage = newValue }
                            modify { yield &storage }
                          }
                        }
                        """
            }

            let assembly = try Self.runXcrunSwiftc(
                arguments: [
                    "swiftc",
                    "-emit-assembly",
                    "-parse-as-library",
                    "-enable-experimental-feature", "CoroutineAccessors",
                    "-module-name", moduleName,
                    "-target", "arm64e-apple-macosx13.0",
                    "-o", "-",
                    "-"
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
                        + (String(bytes: errorData, encoding: .utf8) ?? "<non-UTF8 output>")
                )
            }
            return String(bytes: outputData, encoding: .utf8) ?? "<non-UTF8 output>"
        }
    }

    private struct ProbeError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Gates the whole suite on a live, exact Swift 6.3 `xcrun swiftc`, mirroring
    /// Scripts/check-swift-abi-constants.sh's own version check. Off that exact
    /// toolchain -- including any non-macOS CI target, where `xcrun` does not
    /// exist -- the suite is skipped rather than failing.
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
        return (String(bytes: data, encoding: .utf8) ?? "").contains("Apple Swift version 6.3")
    }()

#endif
