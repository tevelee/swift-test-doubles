import Testing
@testable import ManualStubGeneratorCore

@Suite struct ManualStubGeneratorTests {
    @Test func infersRoutesForArgumentTypeOverloads() throws {
        let output = try render(
            """
            protocol Renderer {
                func render(_ value: Int) -> String
                func render(_ value: String) -> String
                subscript(_ value: Int) -> String { get set }
            }
            """,
            protocolName: "Renderer"
        )

        #expect(output.contains("func render(_ value: Int) -> String { stub.call(value) }"))
        #expect(output.contains("func render(_ value: String) -> String { stub.call(value) }"))
        #expect(output.contains("set { stub.call(value, newValue) }"))
        #expect(
            output.contains(
                "struct RendererStubConformer: Renderer, AutomaticStubConformer"
            )
        )
        #expect(output.contains("typealias StubbedProtocol = any Renderer"))
        #expect(
            output.contains(
                "static func eraseToStubbedProtocol(_ conformer: RendererStubConformer) -> StubbedProtocol"
            )
        )
        #expect(
            output.contains(
                "typealias RendererStub = CompiledStub<RendererStubConformer>"
            )
        )
        #expect(output.contains("static func automatic()") == false)
        #expect(output.contains("fallingBackTo:") == false)
        #expect(output.contains("erasingWith:") == false)
        #expect(output.contains("ManualRouteID") == false)
    }

    @Test func emitsTypedThrowsForEveryEffectCombination() throws {
        let output = try render(
            """
            protocol Loader {
                var token: String { get throws(LoadFailure) }
                func save(_ value: Int) throws(LoadFailure)
                func refresh(_ value: Int) async throws(LoadFailure) -> String
            }
            """,
            protocolName: "Loader"
        )

        #expect(output.contains("try stub.throwingCall(throwing: LoadFailure.self)"))
        #expect(output.contains("try stub.throwingCall(value, throwing: LoadFailure.self)"))
        #expect(
            output.contains(
                "try await stub.throwingCall(value, throwing: LoadFailure.self)"
            )
        )
    }

    @Test func preservesGetterEffectsInPropertiesAndSubscripts() throws {
        for effects in ["async", "throws", "async throws", "throws(LoadFailure)", "async throws(LoadFailure)"] {
            let output = try render(
                """
                protocol Loader {
                    var value: Int { get \(effects) }
                    subscript(_ index: Int) -> Int { get \(effects) }
                }
                """,
                protocolName: "Loader"
            )
            #expect(output.contains("var value: Int { get \(effects) {"))
            #expect(output.contains("subscript(_ index: Int) -> Int { get \(effects) {"))
        }
    }

    @Test func preservesImportsNeededByGeneratedSignatures() throws {
        let output = try render(
            """
            import Foundation

            protocol PayloadSource {
                func load() -> Data
            }
            """,
            protocolName: "PayloadSource"
        )

        #expect(output.hasPrefix("import Foundation\n\n"))
    }

    @Test func preservesRestrictedAccessForMacroPeers() throws {
        let output = try render(
            """
            private protocol SecretSource {
                func load() -> String
            }
            """,
            protocolName: "SecretSource"
        )

        #expect(output.contains("private struct SecretSourceStubConformer"))
        #expect(output.contains("private typealias SecretSourceStub"))
    }

    @Test func actorProtocolsGenerateGenuineActorConformers() throws {
        let output = try render(
            """
            protocol ImageLoader: Sendable, Actor {
                func load(_ identifier: Int) -> String
            }
            """,
            protocolName: "ImageLoader"
        )

        #expect(
            output.contains(
                "actor ImageLoaderStubConformer: ImageLoader, AutomaticStubConformer"
            )
        )
        #expect(
            output.contains(
                "init(stub: CompiledStub<ImageLoaderStubConformer>) { self.stub = stub }"
            )
        )
        #expect(output.contains("struct ImageLoaderStubConformer") == false)
    }

    @Test func emitsImplicitGettersForReadOnlySynchronousRequirements() throws {
        let output = try render(
            """
            protocol Counter {
                var value: Int { get }
                subscript(_ index: Int) -> String { get }
            }
            """,
            protocolName: "Counter"
        )

        #expect(output.contains("var value: Int { stub.call() }"))
        #expect(output.contains("subscript(_ index: Int) -> String { stub.call(index) }"))
    }

    @Test func preservesInoutForwardingWhileRoutingItsStaticType() throws {
        let output = try render(
            """
            protocol Mutator {
                func mutate(_ value: inout Int)
            }
            """,
            protocolName: "Mutator"
        )

        #expect(output.contains("stub.call(&value)"))
    }

    @Test func rejectsStaticAndInitializerRequirements() {
        for requirement in [
            "static func shared() -> Int",
            "init(seed: Int)"
        ] {
            #expect(throws: ManualStubGeneratorError.self) {
                try render(
                    "protocol Shared { \(requirement) }",
                    protocolName: "Shared"
                )
            }
        }
    }

    @Test func reportsRecognizedDeclarationsItCannotParse() {
        do {
            _ = try render(
                "protocol Broken { func missingParentheses }",
                protocolName: "Broken"
            )
            Issue.record("Expected generation to fail")
        } catch let error as ManualStubGeneratorError {
            #expect(error.localizedDescription.contains("missingParentheses"))
            #expect(error.localizedDescription.contains("could not be parsed"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func reportsAMissingProtocol() {
        #expect(throws: ManualStubGeneratorError.self) {
            try render("protocol Other {}", protocolName: "Missing")
        }
    }

    @Test func batchGenerationFindsEveryProtocolInDeterministicSourceOrder() throws {
        let result = try ManualStubBatchGenerator(
            sources: [
                .init(
                    identifier: "B.swift",
                    contents:
                        """
                        import Foundation
                        protocol Second { var value: Int { get } }
                        """
                ),
                .init(
                    identifier: "A.swift",
                    contents:
                        """
                        import Foundation
                        import Dispatch

                        // protocol CommentedOut {}
                        let example = "protocol InAString {}"
                        protocol First {
                            func load(_ id: Int) -> String
                        }
                        """
                )
            ]
        ).render(importingTestDoubles: false)

        #expect(result.generatedProtocolNames == ["First", "Second"])
        #expect(result.source.contains("FirstStubConformer"))
        #expect(result.source.contains("SecondStubConformer"))
        #expect(result.source.contains("CommentedOutStubConformer") == false)
        #expect(result.source.contains("InAStringStubConformer") == false)
        #expect(result.source.contains("import Foundation\nimport Dispatch"))
        #expect(result.source.components(separatedBy: "import Foundation").count == 2)
    }

    @Test func batchGenerationReportsUnsupportedProtocolsWhileGeneratingEligibleOnes() throws {
        let result = try ManualStubBatchGenerator(
            sources: [
                .init(
                    identifier: "Services.swift",
                    contents:
                        """
                        protocol Eligible {
                            func load() -> Int
                        }
                        protocol NeedsSharedState {
                            static func shared() -> Int
                        }
                        """
                )
            ]
        ).render(importingTestDoubles: false)

        #expect(result.generatedProtocolNames == ["Eligible"])
        #expect(result.skippedProtocols.map(\.name) == ["NeedsSharedState"])
        #expect(result.skippedProtocols[0].reason.contains("static requirements"))
    }

    @Test func batchGenerationRejectsDuplicateProtocolNames() {
        #expect(throws: ManualStubGeneratorError.self) {
            try ManualStubBatchGenerator(
                sources: [
                    .init(identifier: "A.swift", contents: "protocol Service {}"),
                    .init(identifier: "B.swift", contents: "protocol Service {}")
                ]
            ).render(importingTestDoubles: false)
        }
    }

    @Test func erasesOpaqueParametersToTheirExistential() throws {
        let output = try render(
            """
            protocol Aggregator {
                func sum(_ numbers: some Sequence<Int>) -> Int
            }
            """,
            protocolName: "Aggregator"
        )

        #expect(output.contains("stub.call(numbers as any Sequence<Int>)"))
    }

    @Test func keepsEveryParameterAfterAClosureTypedParameter() throws {
        let output = try render(
            """
            protocol Logger {
                func log(_ message: @escaping () -> String, file: String, line: Int)
            }
            """,
            protocolName: "Logger"
        )

        #expect(output.contains("stub.call(message, file, line)"))
    }

    @Test func forwardsAutoclosuresThroughTheirPosition() throws {
        let output = try render(
            """
            protocol Logger {
                func log(_ level: Int, _ message: @autoclosure () -> String, line: Int)
                func trace(_ message: @autoclosure () throws -> String) rethrows
            }
            """,
            protocolName: "Logger"
        )

        #expect(output.contains("stub.call(level, stub.deferredArgument(at: 1, message), line)"))
        #expect(output.contains("try stub.deferredArgument(at: 0, message)"))
    }

    @Test func lendsNonescapingClosuresAndRethrowsTheirErrors() throws {
        let output = try render(
            """
            protocol Transformer {
                func map(_ values: [Int], transform: (Int) throws -> Int) rethrows -> [Int]
            }
            """,
            protocolName: "Transformer"
        )

        #expect(output.contains("try withoutActuallyEscaping(transform) { transform in"))
        #expect(output.contains("BorrowedClosure(transform, parameter: \"transform\")"))
        #expect(output.contains("defer { transformBorrow.end() }"))
        #expect(output.contains("try stub.rethrowingCall(borrowing: transformBorrow)"))
        #expect(output.contains("stub.throwingCall(values, transformProxy)"))
    }

    @Test func rejectsRethrowingRequirementsWithoutANonescapingClosure() {
        #expect(throws: ManualStubGeneratorError.self) {
            try render(
                """
                protocol Loader {
                    func load(_ body: @escaping () throws -> Void) rethrows
                }
                """,
                protocolName: "Loader"
            )
        }
    }

    @Test func classBoundProtocolsGenerateFinalClasses() throws {
        let output = try render(
            """
            protocol BaseDelegate: AnyObject {
                func didFinish()
            }

            protocol DetailDelegate: BaseDelegate {
                func didCancel()
            }
            """,
            protocolName: "DetailDelegate"
        )

        #expect(output.contains("final class DetailDelegateStubConformer: DetailDelegate"))
        #expect(output.contains("init(stub: CompiledStub<DetailDelegateStubConformer>) { self.stub = stub }"))
        #expect(output.contains("func didCancel() { stub.call() }"))
        #expect(output.contains("func didFinish() { stub.call() }"))
    }

    @Test func globalActorProtocolsIsolateEachWitness() throws {
        let output = try render(
            """
            @MainActor public protocol Router {
                func push(_ screen: String)
                nonisolated func identifier() -> String
            }
            """,
            protocolName: "Router"
        )

        #expect(output.contains("nonisolated struct RouterStubConformer: Router"))
        #expect(output.contains("@MainActor func push(_ screen: String) { stub.call(screen) }"))
        #expect(output.contains("@MainActor nonisolated") == false)
    }

    @Test func associatedTypesGenerateGenericConformers() throws {
        let output = try render(
            """
            protocol Cache<Key, Value> {
                associatedtype Key: Hashable
                associatedtype Value = String
                func value(for key: Key) -> Value?
            }
            """,
            protocolName: "Cache"
        )

        #expect(output.contains("struct CacheStubConformer<Key: Hashable, Value>: Cache"))
        #expect(output.contains("typealias StubbedProtocol = any Cache<Key, Value>"))
        #expect(output.contains("static var compilerEvidence"))
        #expect(output.contains("runtimeConstruction: .automaticDiscovery"))
        #expect(
            output.contains(
                "typealias CacheStub<Key: Hashable, Value> = CompiledStub<CacheStubConformer<Key, Value>>"
            )
        )
    }

    @Test func batchGenerationImportsTheModulesDeclaringItsProtocols() throws {
        let result = try ManualStubBatchGenerator(
            sources: [
                .init(
                    identifier: "App/Services.swift",
                    contents: """
                        import Foundation
                        protocol Repository { func load() -> Data }
                        private protocol Hidden { func secret() }
                        """,
                    module: "App"
                )
            ],
            additionalImports: ["import Analytics"]
        ).render()

        #expect(result.generatedProtocolNames == ["Repository"])
        #expect(result.skippedProtocols.isEmpty)
        #expect(result.source.contains("import Foundation"))
        #expect(result.source.contains("@testable import App"))
        #expect(result.source.contains("import Analytics"))
        #expect(result.source.contains("import TestDoubles"))
    }

    private func render(_ source: String, protocolName: String) throws -> String {
        try ManualStubGenerator(
            protocolName: protocolName,
            source: source
        ).render(importingTestDoubles: false)
    }
}
