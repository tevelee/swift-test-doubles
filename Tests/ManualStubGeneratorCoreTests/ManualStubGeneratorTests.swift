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
        #expect(output.contains("struct RendererStubConformer"))
        #expect(
            output.contains(
                "typealias RendererStub = ManualStub<RendererStubConformer>"
            )
        )
        #expect(
            output.contains(
                "static func automatic() -> Stub<any Renderer>"
            )
        )
        #expect(
            output.contains(
                "Stub(fallingBackTo: RendererStubConformer.self, erasingWith: { $0 })"
            )
        )
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

    private func render(_ source: String, protocolName: String) throws -> String {
        try ManualStubGenerator(
            protocolName: protocolName,
            source: source
        ).render(importingTestDoubles: false)
    }
}
