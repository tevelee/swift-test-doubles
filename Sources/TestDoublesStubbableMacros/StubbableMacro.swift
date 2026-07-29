#if TESTDOUBLES_STUBBABLE_MACROS
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

            do {
                let generatedSource = try ManualStubGenerator(
                    protocolName: protocolDeclaration.name.text,
                    source: protocolDeclaration.description
                )
                .render(importingTestDoubles: false)
                return generatedDeclarations(from: generatedSource)
            } catch let error as ManualStubGeneratorError {
                context.diagnose(
                    Diagnostic(
                        node: diagnosticNode(
                            for: error.requirement,
                            in: protocolDeclaration
                        ),
                        message: StubbableDiagnostic(
                            message: error.localizedDescription,
                            id: "unsupported-requirement"
                        )
                    )
                )
                return []
            }
        }

        private static func generatedDeclarations(
            from source: String
        ) -> [DeclSyntax] {
            guard
                let aliasSeparator = source.range(
                    of: "\n\ntypealias ",
                    options: .backwards
                )
            else {
                return [DeclSyntax(stringLiteral: source)]
            }
            let conformer = String(source[..<aliasSeparator.lowerBound])
            let alias =
                "typealias "
                + source[aliasSeparator.upperBound...]
            return [
                DeclSyntax(stringLiteral: conformer),
                DeclSyntax(stringLiteral: alias)
            ]
        }

        private static func diagnosticNode(
            for requirement: String?,
            in declaration: ProtocolDeclSyntax
        ) -> Syntax {
            guard let requirement else { return Syntax(declaration) }
            let normalizedRequirement = normalize(requirement)
            let matchingMember = declaration.memberBlock.members.first { member in
                normalize(member.decl.description) == normalizedRequirement
            }
            return matchingMember.map { Syntax($0.decl) } ?? Syntax(declaration)
        }

        private static func normalize(_ source: String) -> String {
            source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    private struct StubbableDiagnostic: DiagnosticMessage {
        let message: String
        let id: String

        static let protocolsOnly = StubbableDiagnostic(
            message: "@Stubbable can only be applied to a protocol declaration.",
            id: "protocols-only"
        )

        var diagnosticID: MessageID {
            MessageID(domain: "TestDoubles.Stubbable", id: id)
        }

        var severity: DiagnosticSeverity { .error }
    }

    @main
    struct TestDoublesStubbablePlugin: CompilerPlugin {
        let providingMacros: [Macro.Type] = [StubbableMacro.self]
    }
#else
    @main
    struct DisabledStubbableMacroPlugin {
        static func main() {}
    }
#endif
