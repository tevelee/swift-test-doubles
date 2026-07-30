#if TESTDOUBLES_STUBBABLE_MACROS
    import SwiftDiagnostics
    import SwiftSyntax
    import SwiftSyntaxMacros

    /// Generates reusable ``ClientDoublePreset`` wiring for a struct whose
    /// stored instance properties are closures.
    public struct StubbableClientMacro: PeerMacro {
        public static func expansion(
            of attribute: AttributeSyntax,
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
                let aliasedEndpoints = try aliasedEndpointNames(
                    from: attribute
                )
                genericShape = try genericClientShape(for: client)
                properties = try clientProperties(
                    in: client,
                    clientType: genericShape.clientType,
                    aliasedEndpoints: aliasedEndpoints
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
            let materializerArguments =
                ["_testDoubleEndpoints: endpoints"]
                + properties.inputs.map { "\($0.name): \($0.name)" }
            let arguments = materializerArguments.enumerated().map {
                index,
                argument in
                let trailingComma =
                    index == materializerArguments.indices.last
                    ? ""
                    : ","
                return indented(
                    argument + trailingComma,
                    by: 8
                )
            }
            .joined(separator: "\n")
            let materializer = [
                "ClientDoublePreset<\(genericShape.clientType)> { endpoints in",
                "    \(genericShape.clientType)(",
                arguments,
                "    )",
                "}"
            ]
            .joined(separator: "\n")

            let preset: String
            if properties.inputs.isEmpty {
                if genericShape.isGeneric {
                    preset = [
                        "\(memberAccess)static var preset: ClientDoublePreset<\(genericShape.clientType)> {",
                        indented(materializer, by: 4),
                        "}"
                    ]
                    .joined(separator: "\n")
                } else {
                    preset =
                        "\(memberAccess)static let preset = \(materializer)"
                }
            } else {
                let parameters = properties.inputs.map {
                    "    \($0.name): \($0.type)"
                }
                .joined(separator: ",\n")
                preset = [
                    "\(memberAccess)static func preset(",
                    parameters,
                    ") -> ClientDoublePreset<\(genericShape.clientType)> {",
                    indented(materializer, by: 4),
                    "}"
                ]
                .joined(separator: "\n")
            }

            let source = [
                "\(access)enum \(clientName)Doubles\(genericShape.declarationClause)\(genericShape.whereClause) {",
                indented(preset, by: 4),
                "}"
            ]
            .joined(separator: "\n")
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
            clientType: String,
            aliasedEndpoints: Set<String>
        ) throws -> ClientProperties {
            let aliases = localTypeAliases(in: client)
            let nestedTypeNames = localTypeNames(in: client)
            var initializerArguments: [ClientInitializerArgument] = []
            var inputs: [ClientInput] = []
            var endpointCount = 0
            var recognizedAliasedEndpoints: Set<String> = []

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
                    let propertyName =
                        identifier.identifier.trimmedDescription
                    let isAliasedEndpoint =
                        aliasedEndpoints.contains(propertyName)
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
                    if isAliasedEndpoint {
                        if variable.bindingSpecifier.text == "let",
                            binding.initializer != nil
                        {
                            throw ClientMacroFailure(
                                node: Syntax(binding),
                                message:
                                    "@StubbableClient cannot replace initialized immutable endpoint '\(propertyName)'. Remove it from 'aliasedEndpoints' to retain its default.",
                                id: "immutable-aliased-endpoint"
                            )
                        }
                        if let function = functionType(
                            from: annotatedType,
                            aliases: aliases
                        ) {
                            try validateParameters(of: function)
                        }
                        let endpoint = AliasedClosureEndpoint(
                            name: propertyName,
                            type: renderedType(
                                annotatedType,
                                clientType: clientType,
                                nestedTypeNames: nestedTypeNames
                            )
                        )
                        recognizedAliasedEndpoints.insert(propertyName)
                        endpointCount += 1
                        initializerArguments.append(
                            .endpoint(.aliased(endpoint))
                        )
                        continue
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
                            name: propertyName,
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
                    try validateParameters(of: function)
                    let endpoint = ClosureEndpoint(
                        name: propertyName,
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
                    initializerArguments.append(
                        .endpoint(.expanded(endpoint))
                    )
                }
            }
            if let unknown =
                aliasedEndpoints
                .subtracting(recognizedAliasedEndpoints)
                .min()
            {
                throw ClientMacroFailure(
                    node: Syntax(client.name),
                    message:
                        "@StubbableClient could not find a stored endpoint named '\(unknown)'.",
                    id: "unknown-aliased-endpoint"
                )
            }
            return ClientProperties(
                initializerArguments: initializerArguments,
                inputs: inputs,
                endpointCount: endpointCount
            )
        }

        private static func validateParameters(
            of function: FunctionTypeSyntax
        ) throws {
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
        }

        private static func aliasedEndpointNames(
            from attribute: AttributeSyntax
        ) throws -> Set<String> {
            guard case .argumentList(let arguments) = attribute.arguments else {
                return []
            }
            var names: Set<String> = []
            for (index, argument) in arguments.enumerated() {
                if index == 0,
                    argument.label?.text != "aliasedEndpoints"
                {
                    throw ClientMacroFailure(
                        node: Syntax(argument),
                        message:
                            "@StubbableClient closure aliases must use the 'aliasedEndpoints:' label.",
                        id: "aliased-endpoint-label"
                    )
                }
                guard
                    let literal = argument.expression.as(
                        StringLiteralExprSyntax.self
                    ),
                    literal.segments.count == 1,
                    let segment = literal.segments.first?.as(
                        StringSegmentSyntax.self
                    )
                else {
                    throw ClientMacroFailure(
                        node: Syntax(argument.expression),
                        message:
                            "@StubbableClient 'aliasedEndpoints' entries must be string literals.",
                        id: "aliased-endpoint-literal"
                    )
                }
                let name = segment.content.text
                guard name.isEmpty == false else {
                    throw ClientMacroFailure(
                        node: Syntax(argument.expression),
                        message:
                            "@StubbableClient endpoint names cannot be empty.",
                        id: "empty-aliased-endpoint"
                    )
                }
                guard names.insert(name).inserted else {
                    throw ClientMacroFailure(
                        node: Syntax(argument.expression),
                        message:
                            "@StubbableClient endpoint '\(name)' is listed more than once.",
                        id: "duplicate-aliased-endpoint"
                    )
                }
            }
            return names
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

    extension StubbableClientMacro: ExtensionMacro {
        public static func expansion(
            of attribute: AttributeSyntax,
            attachedTo declaration: some DeclGroupSyntax,
            providingExtensionsOf type: some TypeSyntaxProtocol,
            conformingTo _: [TypeSyntax],
            in _: some MacroExpansionContext
        ) throws -> [ExtensionDeclSyntax] {
            guard let client = declaration.as(StructDeclSyntax.self) else {
                return []
            }
            guard
                let aliasedEndpoints = try? aliasedEndpointNames(
                    from: attribute
                ),
                let genericShape = try? genericClientShape(for: client),
                let properties = try? clientProperties(
                    in: client,
                    clientType: genericShape.clientType,
                    aliasedEndpoints: aliasedEndpoints
                ),
                properties.endpointCount > 0
            else {
                return []
            }

            let parameters =
                [
                    "_testDoubleEndpoints endpoints: ClientStubEndpoints<Self>"
                ] + properties.inputs.map { "\($0.name): \($0.type)" }
            let renderedParameters = parameters.enumerated().map {
                index,
                parameter in
                let trailingComma =
                    index == parameters.indices.last ? "" : ","
                return "        \(parameter)\(trailingComma)"
            }
            .joined(separator: "\n")
            let assignments = properties.initializerArguments.map {
                indented(
                    $0.renderAssignment(
                        clientType: genericShape.clientType
                    ),
                    by: 8
                )
            }
            .joined(separator: "\n")
            let source = [
                "extension \(type.trimmedDescription) {",
                "    fileprivate init(",
                renderedParameters,
                "    ) {",
                assignments,
                "    }",
                "}"
            ]
            .joined(separator: "\n")
            guard
                let generated = DeclSyntax(stringLiteral: source).as(
                    ExtensionDeclSyntax.self
                )
            else {
                return []
            }
            return [generated]
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
        case endpoint(ClientEndpoint)
        case input(ClientInput)

        func renderAssignment(clientType: String) -> String {
            switch self {
                case .endpoint(let endpoint):
                    return "self.\(endpoint.name) = "
                        + endpoint.renderFactory(clientType: clientType)
                case .input(let input):
                    return "self.\(input.name) = \(input.name)"
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

    private enum ClientEndpoint {
        case expanded(ClosureEndpoint)
        case aliased(AliasedClosureEndpoint)

        var name: String {
            switch self {
                case .expanded(let endpoint):
                    endpoint.name
                case .aliased(let endpoint):
                    endpoint.name
            }
        }

        func renderFactory(clientType: String) -> String {
            switch self {
                case .expanded(let endpoint):
                    endpoint.renderFactory(clientType: clientType)
                case .aliased(let endpoint):
                    endpoint.renderFactory()
            }
        }
    }

    private struct AliasedClosureEndpoint {
        let name: String
        let type: String

        func renderFactory() -> String {
            [
                "endpoints.endpoint(",
                "    \"\(name)\",",
                "    as: \(type).self,",
                "    forwarding: {",
                "        $0.\(name)",
                "    }",
                ")"
            ]
            .joined(separator: "\n")
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
                let effects =
                    (isAsync ? " async" : "")
                    + " throws(\(thrownError))"
                let parameterLines = (["live: \(clientType)"] + typedParameters)
                    .enumerated()
                    .map { index, parameter in
                        let trailingComma =
                            index == typedParameters.count ? "" : ","
                        return "        \(parameter)\(trailingComma)"
                    }
                closure =
                    ([
                        "{",
                        "    ("
                    ] + parameterLines + [
                        "    )\(effects) -> \(resultType) in",
                        "        \(callPrefix)live.\(name)(\(callArguments))",
                        "}"
                    ])
                    .joined(separator: "\n")
            } else {
                let parameters = (["live"] + argumentNames)
                    .joined(separator: ", ")
                closure = [
                    "{ \(parameters) in",
                    "    \(callPrefix)live.\(name)(\(callArguments))",
                    "}"
                ]
                .joined(separator: "\n")
            }

            let typedThrowingLine = thrownError.map {
                "    throwing: \($0).self,"
            }
            var lines = [
                "endpoints.\(factory)(",
                "    \"\(name)\","
            ]
            if let typedThrowingLine {
                lines.append(typedThrowingLine)
            }
            lines.append("    forwarding: \(indented(closure, by: 4).dropFirst(4))")
            lines.append(")")
            return lines.joined(separator: "\n")
        }
    }

    private func indented(_ source: String, by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return
            source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
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
