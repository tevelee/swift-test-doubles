import InternalRuntimeContract

/// Lock-agnostic method metadata owned and synchronized by ``StubRecorder``.
struct ManualMethodCatalog {
    private struct ManualMethodIdentity: Hashable {
        let route: ManualMethodRouteIdentity
        let kind: RuntimeRequirementKind
        let resultType: ObjectIdentifier
        let isAsync: Bool
        let isThrowing: Bool
    }

    private var runtimeMethods: [RuntimeMethod]
    private let modifyDispatchDescriptors: [Int: RuntimeModifyDispatch]
    private var manualMethodsByIdentity: [ManualMethodIdentity: RuntimeMethod] = [:]

    init(
        methods: [RuntimeMethod],
        modifyDispatchDescriptors: [Int: RuntimeModifyDispatch]
    ) {
        runtimeMethods = methods
        self.modifyDispatchDescriptors = modifyDispatchDescriptors
    }

    func method(at index: Int) -> RuntimeMethod? {
        guard runtimeMethods.indices.contains(index) else { return nil }
        return runtimeMethods[index]
    }

    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: RuntimeMethod, setter: RuntimeMethod)? {
        guard let descriptor = modifyDispatchDescriptors[getterIndex],
            let getter = method(at: descriptor.getterSlot),
            let setter = method(at: descriptor.setterSlot)
        else {
            return nil
        }
        return (getter, setter)
    }

    mutating func internManualMethod(
        route: ManualMethodRouteIdentity,
        kind: RuntimeRequirementKind,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> RuntimeMethod {
        let identity = ManualMethodIdentity(
            route: route,
            kind: kind,
            resultType: ObjectIdentifier(returnType),
            isAsync: isAsync,
            isThrowing: isThrowing
        )
        if let existing = manualMethodsByIdentity[identity] {
            return existing
        }
        let descriptor = RuntimeMethod(
            kind: kind,
            receiver: .instance,
            origin: .manual,
            name: route.signature,
            slot: runtimeMethods.count,
            arguments: [],
            result: RuntimeValue(
                type: returnType,
                convention: .concrete,
                associatedTypeUse: .none
            ),
            typedErrorType: nil,
            typedErrorAssociatedTypeUse: nil,
            selfIsClassConstrained: false,
            isThrowing: isThrowing,
            isAsync: isAsync,
            hasReliableThrowing: true,
            signatureDescription: "manual \(route.signature)"
        )
        runtimeMethods.append(descriptor)
        manualMethodsByIdentity[identity] = descriptor
        return descriptor
    }

    func diagnosticSignature(
        method index: Int,
        matchers: [ParameterMatcher]
    ) -> String {
        let name = method(at: index)?.name ?? "method_\(index)"
        let matcherList = matchers.map(\.diagnosticDescription).joined(separator: ", ")
        return "\(name)(\(matcherList))"
    }
}
