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

    private func render(_ source: String, protocolName: String) throws -> String {
        try ManualStubGenerator(
            protocolName: protocolName,
            source: source
        ).render(importingTestDoubles: false)
    }
}
