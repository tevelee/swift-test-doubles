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
    let kind: StubRequirementKind
    let name: String
    let index: Int
    let argumentTypes: [Any.Type]
    let returnType: Any.Type
    let argumentLayouts: [ABIClass]
    let returnLayout: ABIClass
    let isThrowing: Bool
    let isAsync: Bool
    let hasReliableThrowing: Bool

    init(
        kind: StubRequirementKind,
        name: String,
        index: Int,
        argumentTypes: [Any.Type],
        returnType: Any.Type,
        isThrowing: Bool = false,
        isAsync: Bool = false,
        hasReliableThrowing: Bool = true
    ) {
        self.kind = kind
        self.name = name
        self.index = index
        self.argumentTypes = argumentTypes
        self.returnType = returnType
        self.argumentLayouts = argumentTypes.map { abiClass(for: $0) }
        self.returnLayout = abiClass(for: returnType, isReturn: true)
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.hasReliableThrowing = hasReliableThrowing
    }

    var signatureDescription: String {
        let effects = [isAsync ? "async" : nil, isThrowing ? "throws" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        let effectSuffix = effects.isEmpty ? "" : " \(effects)"
        let uncertaintySuffix = hasReliableThrowing ? "" : " [throwing effect unavailable]"
        let result = runtimeTypeName(returnType)
        switch kind {
        case .method:
            let arguments = argumentTypes.map(runtimeTypeName).joined(separator: ", ")
            return "method (\(arguments))\(effectSuffix)\(uncertaintySuffix) -> \(result)"
        case .getter:
            return "getter\(effectSuffix)\(uncertaintySuffix) -> \(result)"
        }
    }

    func hasSameSignature(as discovered: Self) -> Bool {
        let effectsMatch = isAsync == discovered.isAsync && (
            discovered.hasReliableThrowing == false || isThrowing == discovered.isThrowing
        )
        return kind == discovered.kind &&
            effectsMatch &&
            sameType(returnType, discovered.returnType) &&
            argumentTypes.count == discovered.argumentTypes.count &&
            zip(argumentTypes, discovered.argumentTypes).allSatisfy(sameType)
    }
}

extension Stub {
    /// Explicitly describes one protocol requirement.
    ///
    /// Requirements must be supplied in protocol declaration order. Use them
    /// when automatic discovery is unavailable or an effectful getter needs its
    /// throwing behavior stated explicitly.
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
            return MethodDescriptor(
                kind: kind,
                name: "requirement_\(index)",
                index: index,
                argumentTypes: argumentTypes,
                returnType: returnType,
                isThrowing: isThrowing,
                isAsync: isAsync
            )
        }
    }
}

func runtimeTypeName(_ type: Any.Type) -> String {
    type == Void.self ? "Swift.Void" : String(reflecting: type)
}

private func sameType(_ lhs: Any.Type, _ rhs: Any.Type) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}
