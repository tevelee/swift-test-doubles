import Echo

enum StubRequirementKind: String, Sendable {
    case method
    case getter

    init?(_ kind: ProtocolRequirement.Kind) {
        switch kind {
        case .method:
            self = .method
        case .getter:
            self = .getter
        default:
            return nil
        }
    }
}

struct MethodDescriptor: Sendable {
    let name: String
    let index: Int
    let qualifiedArgs: [String]
    let qualifiedRet: String
    let isThrowing: Bool
    let isAsync: Bool
    let argumentTypes: [Any.Type]?
    let returnType: Any.Type?

    init(
        name: String,
        index: Int,
        qualifiedArgs: [String],
        qualifiedRet: String,
        isThrowing: Bool = false,
        isAsync: Bool = false,
        argumentTypes: [Any.Type]? = nil,
        returnType: Any.Type? = nil
    ) {
        self.name = name
        self.index = index
        self.qualifiedArgs = qualifiedArgs
        self.qualifiedRet = qualifiedRet
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.argumentTypes = argumentTypes
        self.returnType = returnType
    }
}

extension Stub {
    /// Describes one protocol requirement when runtime signature discovery is
    /// unavailable. Requirements must be supplied in protocol declaration
    /// order.
    public struct Requirement: Sendable {
        let kind: StubRequirementKind
        let argumentTypes: [Any.Type]
        let returnType: Any.Type
        let isThrowing: Bool
        let isAsync: Bool

        /// Describes a method requirement.
        public static func method<each Argument, Result>(
            _ arguments: repeat (each Argument).Type,
            returning result: Result.Type,
            isThrowing: Bool = false,
            isAsync: Bool = false
        ) -> Self {
            var argumentTypes: [Any.Type] = []
            for argument in repeat each arguments {
                argumentTypes.append(argument)
            }
            return Self(
                kind: .method,
                argumentTypes: argumentTypes,
                returnType: result,
                isThrowing: isThrowing,
                isAsync: isAsync
            )
        }

        /// Describes a property getter requirement.
        public static func getter<Value>(
            _ value: Value.Type,
            isThrowing: Bool = false,
            isAsync: Bool = false
        ) -> Self {
            Self(
                kind: .getter,
                argumentTypes: [],
                returnType: value,
                isThrowing: isThrowing,
                isAsync: isAsync
            )
        }
        func descriptor(index: Int) -> MethodDescriptor {
            let argumentNames = argumentTypes.map(runtimeTypeName)
            let returnName = runtimeTypeName(returnType)
            return MethodDescriptor(
                name: "requirement_\(index)",
                index: index,
                qualifiedArgs: argumentNames,
                qualifiedRet: returnName,
                isThrowing: isThrowing,
                isAsync: isAsync,
                argumentTypes: argumentTypes,
                returnType: returnType
            )
        }
    }
}

private func runtimeTypeName(_ type: Any.Type) -> String {
    type == Void.self ? "Swift.Void" : String(reflecting: type)
}
