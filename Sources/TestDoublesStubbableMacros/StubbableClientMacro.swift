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
            let genericShape: GenericClientShape
            let properties: ClientProperties
            do {
                genericShape = try genericClientShape(for: client)
                properties = try clientProperties(
                    in: client,
                    clientType: genericShape.clientType
                )
            } catch let failure as ClientMacroFailure {
                diagnose(
                    failure.node,
                    failure.message,
                    id: failure.id,
                    in: context
                )
                return []
            }
            guard properties.endpointCount > 0 else {
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
            let arguments = properties.initializerArguments.map {
                "            \($0.render(clientType: genericShape.clientType))"
            }
            .joined(separator: ",\n")
            let materializer =
                """
                ClientDoublePreset<\(genericShape.clientType)> { endpoints in
                        \(genericShape.clientType)(
                \(arguments)
                        )
                    }
                """

            let preset: String
            if properties.inputs.isEmpty {
                if genericShape.isGeneric {
                    preset =
                        """
                        \(memberAccess)static var preset: ClientDoublePreset<\(genericShape.clientType)> {
                            \(materializer)
                        }
                        """
                } else {
                    preset =
                        """
                        \(memberAccess)static let preset = \(materializer)
                        """
                }
            } else {
                let parameters = properties.inputs.map {
                    "        \($0.name): \($0.type)"
                }
                .joined(separator: ",\n")
                preset =
                    """
                    \(memberAccess)static func preset(
                    \(parameters)
                    ) -> ClientDoublePreset<\(genericShape.clientType)> {
                        \(materializer)
                    }
                    """
            }

            let source =
                """
                \(access)enum \(clientName)Doubles\(genericShape.declarationClause)\(genericShape.whereClause) {
                    \(preset)
                }
                """
            return [DeclSyntax(stringLiteral: source)]
        }

        private static func genericClientShape(
            for client: StructDeclSyntax
        ) throws -> GenericClientShape {
            guard let clause = client.genericParameterClause else {
                return GenericClientShape(
                    declarationClause: "",
                    whereClause: "",
                    clientType: client.name.text,
                    isGeneric: false
                )
            }
            if let unsupported = clause.parameters.first(where: {
                $0.specifier != nil
            }) {
                throw ClientMacroFailure(
                    node: Syntax(unsupported),
                    message:
                        "@StubbableClient supports ordinary generic type parameters, but not parameter packs or value parameters.",
                    id: "generic-parameter"
                )
            }

            let arguments = clause.parameters.map {
                $0.name.trimmedDescription
            }
            .joined(separator: ", ")
            let whereClause =
                client.genericWhereClause.map {
                    " \($0.trimmedDescription)"
                } ?? ""
            return GenericClientShape(
                declarationClause: clause.trimmedDescription,
                whereClause: whereClause,
                clientType: "\(client.name.text)<\(arguments)>",
                isGeneric: true
            )
        }

        private static func clientProperties(
            in client: StructDeclSyntax,
            clientType: String
        ) throws -> ClientProperties {
            let aliases = localTypeAliases(in: client)
            let nestedTypeNames = localTypeNames(in: client)
            var initializerArguments: [ClientInitializerArgument] = []
            var inputs: [ClientInput] = []
            var endpointCount = 0

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
                    guard
                        let function = functionType(
                            from: annotatedType,
                            aliases: aliases
                        )
                    else {
                        if binding.initializer != nil {
                            continue
                        }
                        let input = ClientInput(
                            name: identifier.identifier.trimmedDescription,
                            type: renderedType(
                                annotatedType,
                                clientType: clientType,
                                nestedTypeNames: nestedTypeNames
                            )
                        )
                        inputs.append(input)
                        initializerArguments.append(.input(input))
                        continue
                    }
                    if variable.bindingSpecifier.text == "let",
                        binding.initializer != nil
                    {
                        continue
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
                    let endpoint = ClosureEndpoint(
                        name: identifier.identifier.trimmedDescription,
                        argumentTypes: function.parameters.map {
                            renderedType(
                                $0.type,
                                clientType: clientType,
                                nestedTypeNames: nestedTypeNames
                            )
                        },
                        resultType: renderedType(
                            function.returnClause.type,
                            clientType: clientType,
                            nestedTypeNames: nestedTypeNames
                        ),
                        isAsync: function.effectSpecifiers?
                            .asyncSpecifier != nil,
                        thrownError: function.effectSpecifiers?
                            .throwsClause?
                            .type.map {
                                renderedType(
                                    $0,
                                    clientType: clientType,
                                    nestedTypeNames: nestedTypeNames
                                )
                            },
                        isThrowing: function.effectSpecifiers?
                            .throwsClause != nil
                    )
                    endpointCount += 1
                    initializerArguments.append(.endpoint(endpoint))
                }
            }
            return ClientProperties(
                initializerArguments: initializerArguments,
                inputs: inputs,
                endpointCount: endpointCount
            )
        }

        private static func functionType(
            from annotatedType: TypeSyntax,
            aliases: [String: TypeSyntax],
            visitedAliases: Set<String> = []
        ) -> FunctionTypeSyntax? {
            var type = annotatedType
            while let attributed = type.as(AttributedTypeSyntax.self) {
                type = attributed.baseType
            }
            if let function = type.as(FunctionTypeSyntax.self) {
                return function
            }
            guard
                let identifier = type.as(IdentifierTypeSyntax.self),
                identifier.genericArgumentClause == nil
            else {
                return nil
            }
            let name = identifier.name.text
            guard
                visitedAliases.contains(name) == false,
                let aliasedType = aliases[name]
            else {
                return nil
            }
            return functionType(
                from: aliasedType,
                aliases: aliases,
                visitedAliases: visitedAliases.union([name])
            )
        }

        private static func localTypeAliases(
            in client: StructDeclSyntax
        ) -> [String: TypeSyntax] {
            client.memberBlock.members.reduce(into: [:]) { aliases, member in
                guard
                    let alias = member.decl.as(TypeAliasDeclSyntax.self),
                    alias.genericParameterClause == nil
                else {
                    return
                }
                aliases[alias.name.text] = alias.initializer.value
            }
        }

        private static func localTypeNames(
            in client: StructDeclSyntax
        ) -> Set<String> {
            client.memberBlock.members.reduce(into: []) { names, member in
                let declaration = member.decl
                if let alias = declaration.as(TypeAliasDeclSyntax.self) {
                    names.insert(alias.name.text)
                } else if let structure = declaration.as(StructDeclSyntax.self) {
                    names.insert(structure.name.text)
                } else if let enumeration = declaration.as(EnumDeclSyntax.self) {
                    names.insert(enumeration.name.text)
                } else if let classDeclaration = declaration.as(ClassDeclSyntax.self) {
                    names.insert(classDeclaration.name.text)
                } else if let actor = declaration.as(ActorDeclSyntax.self) {
                    names.insert(actor.name.text)
                } else if let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self) {
                    names.insert(protocolDeclaration.name.text)
                }
            }
        }

        private static func renderedType(
            _ type: TypeSyntax,
            clientType: String,
            nestedTypeNames: Set<String>
        ) -> String {
            NestedClientTypeQualifier(
                clientType: clientType,
                nestedTypeNames: nestedTypeNames
            )
            .rewrite(type)
            .trimmedDescription
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

    private struct GenericClientShape {
        let declarationClause: String
        let whereClause: String
        let clientType: String
        let isGeneric: Bool
    }

    private struct ClientProperties {
        let initializerArguments: [ClientInitializerArgument]
        let inputs: [ClientInput]
        let endpointCount: Int
    }

    private enum ClientInitializerArgument {
        case endpoint(ClosureEndpoint)
        case input(ClientInput)

        func render(clientType: String) -> String {
            switch self {
                case .endpoint(let endpoint):
                    return
                        "\(endpoint.name): "
                        + endpoint.renderFactory(clientType: clientType)
                case .input(let input):
                    return "\(input.name): \(input.name)"
            }
        }
    }

    private struct ClientInput {
        let name: String
        let type: String
    }

    private final class NestedClientTypeQualifier: SyntaxRewriter {
        private let clientType: String
        private let nestedTypeNames: Set<String>

        init(
            clientType: String,
            nestedTypeNames: Set<String>
        ) {
            self.clientType = clientType
            self.nestedTypeNames = nestedTypeNames
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
            guard nestedTypeNames.contains(node.name.text) else {
                return super.visit(node)
            }
            return TypeSyntax(
                stringLiteral: "\(clientType).\(node.trimmedDescription)"
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

        func renderFactory(clientType: String) -> String {
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
                let parameters = (["live: \(clientType)"] + typedParameters)
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
