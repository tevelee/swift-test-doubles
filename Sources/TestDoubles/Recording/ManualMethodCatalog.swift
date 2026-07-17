/// Lock-agnostic method metadata owned and synchronized by ``StubRecorder``.
struct ManualMethodCatalog {
    private struct ManualMethodIdentity: Hashable {
        let route: ManualMethodRouteIdentity
        let kind: StubRequirementKind
        let resultType: ObjectIdentifier
        let isAsync: Bool
        let isThrowing: Bool
    }

    private var runtimeMethods: [MethodDescriptor]
    private let modifyDispatchDescriptors: [Int: ModifyDispatchDescriptor]
    private var manualMethodsByIdentity: [ManualMethodIdentity: MethodDescriptor] = [:]

    init(
        methods: [MethodDescriptor],
        modifyDispatchDescriptors: [Int: ModifyDispatchDescriptor]
    ) {
        runtimeMethods = methods
        self.modifyDispatchDescriptors = modifyDispatchDescriptors
    }

    func method(at index: Int) -> MethodDescriptor? {
        guard runtimeMethods.indices.contains(index) else { return nil }
        return runtimeMethods[index]
    }

    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: MethodDescriptor, setter: MethodDescriptor)? {
        guard let descriptor = modifyDispatchDescriptors[getterIndex],
            let getter = method(at: descriptor.getterDispatchIndex),
            let setter = method(at: descriptor.setterDispatchIndex)
        else {
            return nil
        }
        return (getter, setter)
    }

    mutating func internManualMethod(
        route: ManualMethodRouteIdentity,
        kind: StubRequirementKind,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> MethodDescriptor {
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
        let descriptor = MethodDescriptor(
            kind: kind,
            origin: .manual,
            name: route.signature,
            index: runtimeMethods.count,
            argumentTypes: [],
            returnType: returnType,
            isThrowing: isThrowing,
            isAsync: isAsync
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
