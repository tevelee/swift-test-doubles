import ManualStubGeneratorCore
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct StubbableMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(declaration),
                    message: StubbableDiagnostic.protocolsOnly
                )
            )
            return []
        }

        let generatedSource = try ManualStubGenerator(
            protocolName: protocolDeclaration.name.text,
            source: protocolDeclaration.description
        )
        .render(importingTestDoubles: false)
        return [DeclSyntax(stringLiteral: generatedSource)]
    }
}

private enum StubbableDiagnostic: String, DiagnosticMessage {
    case protocolsOnly = "@Stubbable can only be applied to a protocol declaration."

    var message: String { rawValue }

    var diagnosticID: MessageID {
        MessageID(domain: "TestDoubles.Stubbable", id: "protocols-only")
    }

    var severity: DiagnosticSeverity { .error }
}

@main
struct TestDoublesStubbablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [StubbableMacro.self]
}
