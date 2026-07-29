#if TESTDOUBLES_STUBBABLE_MACROS
    import SwiftDiagnostics
    import SwiftSyntax
    import SwiftSyntaxMacros

    /// Generates reusable ``ClientDoublePreset`` wiring for a struct whose
    /// stored instance properties are closures.
    public struct StubbableClientMacro: PeerMacro {
        public static func expansion(
            of _: AttributeSyntax,
            providingPeersOf declaration: some DeclSyntaxProtocol,
            in context: some MacroExpansionContext
        ) throws -> [DeclSyntax] {
            guard let client = declaration.as(StructDeclSyntax.self) else {
                diagnose(
                    declaration,
                    "@StubbableClient can only be applied to a struct declaration.",
                    id: "structs-only",
                    in: context
                )
                return []
            }
            guard client.genericParameterClause == nil,
                client.genericWhereClause == nil
            else {
                diagnose(
                    client,
                    "@StubbableClient does not yet support generic client structs.",
                    id: "generic-client",
                    in: context
                )
                return []
            }

            let endpoints: [ClosureEndpoint]
            do {
                endpoints = try closureEndpoints(in: client)
            } catch let failure as ClientMacroFailure {
                diagnose(
                    failure.node,
                    failure.message,
                    id: failure.id,
                    in: context
                )
                return []
            }
            guard endpoints.isEmpty == false else {
                diagnose(
                    client,
                    "@StubbableClient requires at least one stored closure property.",
                    id: "no-endpoints",
                    in: context
                )
                return []
            }

            let clientName = client.name.text
            let access = generatedAccessModifier(for: client)
            let memberAccess =
                access == "public " || access == "package "
                ? access
                : ""
            let arguments = endpoints.map {
                "            \($0.name): \($0.renderFactory(clientName: clientName))"
            }
            .joined(separator: ",\n")
            let source =
                """
                \(access)enum \(clientName)Doubles {
                    \(memberAccess)static let preset = ClientDoublePreset<\(clientName)> { endpoints in
                        \(clientName)(
                \(arguments)
                        )
                    }
                }
                """
            return [DeclSyntax(stringLiteral: source)]
        }

        private static func closureEndpoints(
            in client: StructDeclSyntax
        ) throws -> [ClosureEndpoint] {
            var endpoints: [ClosureEndpoint] = []
            for member in client.memberBlock.members {
                guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                    continue
                }
                if variable.modifiers.contains(where: {
                    $0.name.text == "static" || $0.name.text == "class"
                }) {
                    continue
                }
                for binding in variable.bindings {
                    guard binding.accessorBlock == nil else {
                        continue
                    }
                    guard
                        let identifier = binding.pattern.as(
                            IdentifierPatternSyntax.self
                        )
                    else {
                        throw ClientMacroFailure(
                            node: Syntax(binding.pattern),
                            message:
                                "@StubbableClient requires identifier-pattern stored properties.",
                            id: "property-pattern"
                        )
                    }
                    guard let annotatedType = binding.typeAnnotation?.type else {
                        if binding.initializer != nil {
                            continue
                        }
                        throw ClientMacroFailure(
                            node: Syntax(binding.pattern),
                            message:
                                "@StubbableClient requires an explicit closure type for stored property '\(identifier.identifier.text)'.",
                            id: "missing-type"
                        )
                    }
                    guard let function = functionType(from: annotatedType) else {
                        if binding.initializer != nil {
                            continue
                        }
                        throw ClientMacroFailure(
                            node: Syntax(annotatedType),
                            message:
                                "@StubbableClient cannot initialize non-closure stored property '\(identifier.identifier.text)' without a default value.",
                            id: "non-closure-property"
                        )
                    }
                    if variable.bindingSpecifier.text == "let",
                        binding.initializer != nil
                    {
                        throw ClientMacroFailure(
                            node: Syntax(binding.pattern),
                            message:
                                "@StubbableClient cannot replace initialized let closure '\(identifier.identifier.text)'.",
                            id: "initialized-let"
                        )
                    }
                    if function.parameters.contains(where: {
                        $0.ellipsis != nil
                            || $0.type.trimmedDescription.hasPrefix("inout ")
                    }) {
                        throw ClientMacroFailure(
                            node: Syntax(function),
                            message:
                                "@StubbableClient does not support variadic or inout closure parameters.",
                            id: "unsupported-parameter"
                        )
                    }
                    endpoints.append(
                        ClosureEndpoint(
                            name: identifier.identifier.trimmedDescription,
                            argumentTypes: function.parameters.map {
                                $0.type.trimmedDescription
                            },
                            resultType: function.returnClause.type
                                .trimmedDescription,
                            isAsync: function.effectSpecifiers?
                                .asyncSpecifier != nil,
                            thrownError: function.effectSpecifiers?
                                .throwsClause?
                                .type?
                                .trimmedDescription,
                            isThrowing: function.effectSpecifiers?
                                .throwsClause != nil
                        )
                    )
                }
            }
            return endpoints
        }

        private static func functionType(
            from annotatedType: TypeSyntax
        ) -> FunctionTypeSyntax? {
            var type = annotatedType
            while let attributed = type.as(AttributedTypeSyntax.self) {
                type = attributed.baseType
            }
            return type.as(FunctionTypeSyntax.self)
        }

        private static func generatedAccessModifier(
            for declaration: StructDeclSyntax
        ) -> String {
            let access = declaration.modifiers.first {
                ["public", "package", "fileprivate", "private"].contains(
                    $0.name.text
                )
            }?
            .name
            .text
            return access.map { "\($0) " } ?? ""
        }

        private static func diagnose(
            _ node: some SyntaxProtocol,
            _ message: String,
            id: String,
            in context: some MacroExpansionContext
        ) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: StubbableClientDiagnostic(
                        message: message,
                        id: id
                    )
                )
            )
        }
    }

    private struct ClosureEndpoint {
        let name: String
        let argumentTypes: [String]
        let resultType: String
        let isAsync: Bool
        let thrownError: String?
        let isThrowing: Bool

        func renderFactory(clientName: String) -> String {
            let factory =
                switch (isAsync, isThrowing) {
                    case (false, false): "function"
                    case (false, true): "throwingFunction"
                    case (true, false): "asyncFunction"
                    case (true, true): "asyncThrowingFunction"
                }
            let typedThrowingArgument =
                thrownError.map {
                    ", throwing: \($0).self"
                } ?? ""
            let argumentNames = argumentTypes.indices.map {
                "argument\($0)"
            }
            let callArguments = argumentNames.joined(separator: ", ")
            let callPrefix =
                switch (isAsync, isThrowing) {
                    case (false, false): ""
                    case (false, true): "try "
                    case (true, false): "await "
                    case (true, true): "try await "
                }

            let closure: String
            if let thrownError {
                let typedParameters = zip(argumentNames, argumentTypes).map {
                    "\($0): \($1)"
                }
                let parameters = (["live: \(clientName)"] + typedParameters)
                    .joined(separator: ", ")
                let effects =
                    (isAsync ? " async" : "")
                    + " throws(\(thrownError))"
                closure =
                    """
                    {
                                (\(parameters))\(effects) -> \(resultType) in
                                \(callPrefix)live.\(name)(\(callArguments))
                            }
                    """
            } else {
                let parameters = (["live"] + argumentNames)
                    .joined(separator: ", ")
                closure =
                    """
                    { \(parameters) in
                                \(callPrefix)live.\(name)(\(callArguments))
                            }
                    """
            }

            return
                """
                endpoints.\(factory)(
                            "\(name)"\(typedThrowingArgument),
                            forwarding: \(closure)
                        )
                """
        }
    }

    private struct ClientMacroFailure: Error {
        let node: Syntax
        let message: String
        let id: String
    }

    private struct StubbableClientDiagnostic: DiagnosticMessage {
        let message: String
        let id: String

        var diagnosticID: MessageID {
            MessageID(domain: "TestDoubles.StubbableClient", id: id)
        }

        var severity: DiagnosticSeverity { .error }
    }
#endif
