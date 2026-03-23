import SwiftSyntax
import SwiftSyntaxMacros

/// `@Mockable` is a peer macro attached to a protocol declaration.
/// It generates:
/// 1. A `<Protocol>Mock` class with stub/verify infrastructure
/// 2. `@convention(thin)` witness thunks for each protocol requirement
/// 3. A static method to build the `any Protocol` existential via Echo
public struct MockableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            throw MacroError("@Mockable can only be applied to protocols")
        }

        let protocolName = protocolDecl.name.text
        let mockClassName = "\(protocolName)Mock"

        // Collect all requirements
        var requirements: [ProtocolRequirement] = []
        for member in protocolDecl.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                requirements.append(.function(funcDecl))
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                requirements.append(.property(varDecl))
            }
        }

        // Generate the mock class
        let mockClass = generateMockClass(
            protocolName: protocolName,
            mockClassName: mockClassName,
            requirements: requirements
        )

        return [DeclSyntax(mockClass)]
    }

    private static func generateMockClass(
        protocolName: String,
        mockClassName: String,
        requirements: [ProtocolRequirement]
    ) -> ClassDeclSyntax {
        var members: [MemberBlockItemSyntax] = []

        // StubRecorder property
        members.append(MemberBlockItemSyntax(
            decl: DeclSyntax("let recorder = StubRecorder()")
        ))

        // Witness thunks array property
        members.append(MemberBlockItemSyntax(
            decl: DeclSyntax("private var _activeRecorder: StubRecorder? { get { Self._activeRecorder } set { Self._activeRecorder = newValue } }")
        ))
        members.append(MemberBlockItemSyntax(
            decl: DeclSyntax("nonisolated(unsafe) private static var _activeRecorder: StubRecorder?")
        ))

        // Generate thunks for each requirement
        for (index, req) in requirements.enumerated() {
            let thunkDecl = generateThunk(
                requirement: req,
                index: index,
                mockClassName: mockClassName
            )
            members.append(MemberBlockItemSyntax(decl: thunkDecl))
        }

        // Generate the thunks() method that returns WitnessThunk array
        let thunksMethod = generateThunksMethod(
            requirements: requirements,
            mockClassName: mockClassName
        )
        members.append(MemberBlockItemSyntax(decl: thunksMethod))

        // Generate asProtocol() method
        let asProtocolMethod = generateAsProtocolMethod(
            protocolName: protocolName,
            mockClassName: mockClassName,
            requirements: requirements
        )
        members.append(MemberBlockItemSyntax(decl: asProtocolMethod))

        // Generate convenience stub methods
        for (index, req) in requirements.enumerated() {
            let stubMethod = generateStubConvenience(requirement: req, index: index)
            if let stubMethod {
                members.append(MemberBlockItemSyntax(decl: stubMethod))
            }
        }

        return ClassDeclSyntax(
            modifiers: [],
            name: TokenSyntax.identifier(mockClassName),
            memberBlock: MemberBlockSyntax(members: MemberBlockItemListSyntax(members))
        )
    }

    private static func generateThunk(
        requirement: ProtocolRequirement,
        index: Int,
        mockClassName: String
    ) -> DeclSyntax {
        switch requirement {
        case .function(let funcDecl):
            return generateFunctionThunk(funcDecl: funcDecl, index: index, mockClassName: mockClassName)
        case .property(let varDecl):
            return generateGetterThunk(varDecl: varDecl, index: index, mockClassName: mockClassName)
        }
    }

    private static func generateFunctionThunk(
        funcDecl: FunctionDeclSyntax,
        index: Int,
        mockClassName: String
    ) -> DeclSyntax {
        let funcName = methodName(from: funcDecl)
        let params = funcDecl.signature.parameterClause.parameters
        let returnType = funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"

        // Build parameter list for the @convention(thin) function
        // Witness convention: (param1, param2, ..., selfPtr, witnessTablePtr) -> ReturnType
        var thinParams: [String] = []
        var argExtractions: [String] = []

        for (i, param) in params.enumerated() {
            let type = param.type.trimmedDescription
            thinParams.append("_ arg\(i): \(type)")
            argExtractions.append("arg\(i)")
        }
        thinParams.append("_ selfPtr: UnsafeRawPointer")
        thinParams.append("_ wtPtr: UnsafeRawPointer")

        let argsArray = argExtractions.isEmpty
            ? "[]"
            : "[\(argExtractions.joined(separator: ", "))]"

        let castLine = returnType == "Void"
            ? "_ = \(mockClassName)._activeRecorder!.dispatch(method: \(index), args: \(argsArray))"
            : "return \(mockClassName)._activeRecorder!.dispatch(method: \(index), args: \(argsArray)) as! \(returnType)"

        // Extract just the parameter names for the closure
        var closureParams: [String] = []
        for (i, _) in params.enumerated() {
            closureParams.append("arg\(i)")
        }
        closureParams.append("selfPtr")
        closureParams.append("wtPtr")

        return DeclSyntax("""
        private static let _thunk\(raw: index): @convention(thin) (\(raw: thinParams.joined(separator: ", "))) -> \(raw: returnType) = { \(raw: closureParams.joined(separator: ", ")) in
                \(raw: castLine)
            }
        """)
    }

    private static func generateGetterThunk(
        varDecl: VariableDeclSyntax,
        index: Int,
        mockClassName: String
    ) -> DeclSyntax {
        let propName = varDecl.bindings.first!.pattern.trimmedDescription
        let propType = varDecl.bindings.first!.typeAnnotation!.type.trimmedDescription

        return DeclSyntax("""
        private static let _thunk\(raw: index): @convention(thin) (_ selfPtr: UnsafeRawPointer, _ wtPtr: UnsafeRawPointer) -> \(raw: propType) = { selfPtr, wtPtr in
                return \(raw: mockClassName)._activeRecorder!.dispatch(method: \(raw: index), args: []) as! \(raw: propType)
            }
        """)
    }

    private static func generateThunksMethod(
        requirements: [ProtocolRequirement],
        mockClassName: String
    ) -> DeclSyntax {
        let thunkEntries = requirements.enumerated().map { (i, _) in
            "WitnessThunk(functionPointer: unsafeBitCast(Self._thunk\(i), to: UnsafeRawPointer.self), requirementIndex: \(i))"
        }.joined(separator: ",\n            ")

        return DeclSyntax("""
        var thunks: [WitnessThunk] {
                [
                    \(raw: thunkEntries)
                ]
            }
        """)
    }

    private static func generateAsProtocolMethod(
        protocolName: String,
        mockClassName: String,
        requirements: [ProtocolRequirement] = []
    ) -> DeclSyntax {
        var nameRegistrations = ""
        for (i, req) in requirements.enumerated() {
            let name: String
            switch req {
            case .function(let f): name = methodName(from: f)
            case .property(let v): name = v.bindings.first!.pattern.trimmedDescription
            }
            nameRegistrations += "recorder.setName(\"\(name)\", for: \(i))\n                "
        }

        return DeclSyntax("""
        func asProtocol(cloning realValue: any \(raw: protocolName)) -> any \(raw: protocolName) {
                Self._activeRecorder = recorder
                \(raw: nameRegistrations)var value = realValue
                let container = withUnsafePointer(to: &value) { ptr in
                    ExistentialBuilder.extractContainer(from: UnsafeRawPointer(ptr))
                }
                let (patchedWT, _) = ExistentialBuilder.patchedWitnessTable(
                    cloning: container.witnessTable,
                    with: thunks
                )
                let mockContainer = ExistentialBuilder.buildContainer(
                    base: container.base,
                    witnessTable: patchedWT
                )
                var result: any \(raw: protocolName) = realValue
                withUnsafeMutablePointer(to: &result) { ptr in
                    ExistentialBuilder.writeContainer(mockContainer, to: UnsafeMutableRawPointer(ptr))
                }
                return result
            }
        """)
    }

    private static func generateStubConvenience(
        requirement: ProtocolRequirement,
        index: Int
    ) -> DeclSyntax? {
        // Convenience methods for stubbing each requirement by name
        switch requirement {
        case .function(let funcDecl):
            let name = methodName(from: funcDecl)
            let returnType = funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"
            if returnType == "Void" {
                return DeclSyntax("""
                func stub_\(raw: funcDecl.name.text)(handler: @escaping ([Any]) -> Void = { _ in }) {
                        recorder.stubFunction("\(raw: name)", at: \(raw: index)) { args in handler(args); return () }
                    }
                """)
            } else {
                return DeclSyntax("""
                func stub_\(raw: funcDecl.name.text)(handler: @escaping ([Any]) -> \(raw: returnType)) {
                        recorder.stubFunction("\(raw: name)", at: \(raw: index)) { args in handler(args) }
                    }
                """)
            }
        case .property(let varDecl):
            let propName = varDecl.bindings.first!.pattern.trimmedDescription
            let propType = varDecl.bindings.first!.typeAnnotation!.type.trimmedDescription
            return DeclSyntax("""
            func stub_\(raw: propName)(returning value: @autoclosure @escaping () -> \(raw: propType)) {
                    recorder.stubGetter("\(raw: propName)", at: \(raw: index), returning: value())
                }
            """)
        }
    }

    static func methodName(from funcDecl: FunctionDeclSyntax) -> String {
        let baseName = funcDecl.name.text
        let params = funcDecl.signature.parameterClause.parameters
        if params.isEmpty {
            return "\(baseName)()"
        }
        let labels = params.map { param in
            let label = param.firstName.text
            return "\(label):"
        }
        return "\(baseName)(\(labels.joined()))"
    }
}

enum ProtocolRequirement {
    case function(FunctionDeclSyntax)
    case property(VariableDeclSyntax)
}

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
