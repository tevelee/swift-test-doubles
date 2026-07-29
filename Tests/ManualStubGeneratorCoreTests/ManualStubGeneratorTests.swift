import Testing
@testable import ManualStubGeneratorCore

@Suite struct ManualStubGeneratorTests {
    @Test func emitsStaticRoutesForArgumentTypeOverloads() throws {
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

        #expect(
            output.contains(
                "stub.call(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value)))"
            )
        )
        #expect(
            output.contains(
                "stub.call(value, newValue, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value), Self.manualStubArgumentType(of: newValue)))"
            )
        )
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
        #expect(
            output.contains(
                "try stub.throwingCall(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value)), throwing: LoadFailure.self)"
            )
        )
        #expect(
            output.contains(
                "try await stub.asyncThrowingCall(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value)), throwing: LoadFailure.self)"
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

        #expect(
            output.contains(
                "stub.call(&value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value)))"
            )
        )
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
