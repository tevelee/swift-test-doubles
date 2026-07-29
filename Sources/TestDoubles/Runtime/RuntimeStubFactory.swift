import InternalRuntimeContract
#if TESTDOUBLES_RUNTIME_STUBS
    import TestDoublesRuntime
    import TestDoublesRuntimeSupport
#endif

/// The public target's opaque gateway to runtime-generated existential values.
///
/// Construction policy and semantic endpoints stay in `TestDoubles`. Runtime
/// preparation receives source-level schemas and returns semantic methods plus
/// opaque materialization storage; descriptors, layouts, and ABI plans do not
/// cross this facade.
enum RuntimeStubFactory {
    #if TESTDOUBLES_RUNTIME_STUBS
        static func takeGlobalInvocationSequence() -> UInt64 {
            RuntimeSymbols.nextGlobalInvocationSequence()
        }
    #endif

    static func makePayload(resources: AnyObject) -> AnyObject {
        #if TESTDOUBLES_RUNTIME_STUBS
            TestDoublesRuntime.RuntimeStubFactory.makePayload(resources: resources)
        #else
            resources
        #endif
    }

    static func makeRecordingPlaceholder<T>(for type: T.Type) -> T? {
        #if TESTDOUBLES_RUNTIME_STUBS
            TestDoublesRuntime.RuntimeStubFactory.makeRecordingPlaceholder(for: type)
        #else
            sourceRecordingPlaceholder(for: type)
        #endif
    }

    static func makeTypedWitnessAdapter<P, Adapter>(
        _ adapter: Adapter,
        invocationType: Stub<P>.Invocation.Type
    ) -> RuntimeTypedWitnessAdapterToken {
        var adapter = adapter
        let word = withUnsafeBytes(of: &adapter) { bytes in
            guard bytes.count >= MemoryLayout<UInt>.size else { return UInt(0) }
            return bytes.load(as: UInt.self)
        }
        let source = RuntimeTypedWitnessAdapterSource(
            functionType: Adapter.self,
            invocationType: invocationType,
            entryPoint: word,
            makeInvocation: { endpoint, slot in
                invocationType.init(endpoint: endpoint, slot: slot)
            }
        )
        return RuntimeTypedWitnessAdapterToken(payload: source)
    }

    struct Storage<P> {
        #if TESTDOUBLES_RUNTIME_STUBS
            private let storage: TestDoublesRuntime.RuntimeStubFactory.Storage<P>

            fileprivate init(storage: TestDoublesRuntime.RuntimeStubFactory.Storage<P>) {
                self.storage = storage
            }

            func materialize() -> P {
                storage.materialize()
            }
        #else
            func materialize() -> P {
                failBecauseRuntimeStubsAreDisabled()
            }
        #endif
    }

    #if TESTDOUBLES_RUNTIME_STUBS
        struct PreparedPlan<P> {
            let methods: [RuntimeMethod]
            let modifyDispatches: [Int: RuntimeModifyDispatch]
            let allowsForwardingFallback: Bool

            private let plan: TestDoublesRuntime.RuntimeStubFactory.PreparedPlan<P>

            fileprivate init(plan: TestDoublesRuntime.RuntimeStubFactory.PreparedPlan<P>) {
                self.plan = plan
                methods = plan.methods
                modifyDispatches = plan.modifyDispatches
                allowsForwardingFallback = plan.allowsForwardingFallback
            }

            fileprivate func materialize(
                endpoint: any RuntimeInvocationEndpoint,
                protocolName: String
            ) throws -> Storage<P> {
                Storage(
                    storage: try plan.materialize(
                        endpoint: endpoint,
                        protocolName: protocolName
                    ))
            }
        }

        struct PreparedDummyPlan<P> {
            let requirements: [RuntimeDummyRequirement]
            private let plan: TestDoublesRuntime.RuntimeStubFactory.PreparedDummyPlan<P>

            fileprivate init(plan: TestDoublesRuntime.RuntimeStubFactory.PreparedDummyPlan<P>) {
                self.plan = plan
                requirements = plan.requirements
            }

            fileprivate func materialize(
                endpoint: any RuntimeInvocationEndpoint,
                protocolName: String
            ) throws -> Storage<P> {
                Storage(
                    storage: try plan.materialize(
                        endpoint: endpoint,
                        protocolName: protocolName
                    ))
            }
        }

        static func prepareStub<P>(
            _ request: RuntimeStubPreparationRequest
        ) throws -> PreparedPlan<P> {
            PreparedPlan(plan: try TestDoublesRuntime.RuntimeStubFactory.prepareStub(request))
        }

        static func prepareForwardingStub<P>(
            to target: P,
            request: RuntimeStubPreparationRequest
        ) throws -> PreparedPlan<P> {
            PreparedPlan(
                plan: try TestDoublesRuntime.RuntimeStubFactory.prepareForwardingStub(
                    to: target,
                    request: request
                ))
        }

        static func prepareDummy<P>(
            _ request: RuntimeProtocolShapeRequest
        ) throws -> PreparedDummyPlan<P> {
            PreparedDummyPlan(plan: try TestDoublesRuntime.RuntimeStubFactory.prepareDummy(request))
        }
    #else
        struct PreparedPlan<P> {
            let methods: [RuntimeMethod]
            let modifyDispatches: [Int: RuntimeModifyDispatch]
            let allowsForwardingFallback: Bool

            fileprivate func materialize(
                endpoint: any RuntimeInvocationEndpoint,
                protocolName: String
            ) throws -> Storage<P> {
                _ = endpoint
                throw runtimeStubsDisabledError(protocolName: protocolName)
            }
        }

        struct PreparedDummyPlan<P> {
            let requirements: [RuntimeDummyRequirement]

            fileprivate func materialize(
                endpoint: any RuntimeInvocationEndpoint,
                protocolName: String
            ) throws -> Storage<P> {
                _ = endpoint
                throw runtimeStubsDisabledError(protocolName: protocolName)
            }
        }

        static func prepareStub<P>(
            _ request: RuntimeStubPreparationRequest
        ) throws -> PreparedPlan<P> {
            throw runtimeStubsDisabledError(protocolName: request.shape.typeDescription)
        }

        static func prepareForwardingStub<P>(
            to target: P,
            request: RuntimeStubPreparationRequest
        ) throws -> PreparedPlan<P> {
            _ = target
            throw runtimeStubsDisabledError(protocolName: request.shape.typeDescription)
        }

        static func prepareDummy<P>(
            _ request: RuntimeProtocolShapeRequest
        ) throws -> PreparedDummyPlan<P> {
            throw runtimeStubsDisabledError(protocolName: request.typeDescription)
        }
    #endif
}

#if !TESTDOUBLES_RUNTIME_STUBS
    private let runtimeStubsDisabledReason =
        "Runtime-generated test doubles are disabled for this build. "
        + "Enable the package's default `RuntimeStubs` trait, or use `ManualStub`."

    private func runtimeStubsDisabledError(protocolName: String) -> StubError {
        .unsupportedProtocolShape(
            protocolName: protocolName,
            reason: runtimeStubsDisabledReason
        )
    }

    // swiftlint:disable:next unavailable_function
    private func failBecauseRuntimeStubsAreDisabled<Result>() -> Result {
        preconditionFailure(runtimeStubsDisabledReason)
    }

    private func sourceRecordingPlaceholder<T>(for type: T.Type) -> T? {
        switch type {
            case is Void.Type: () as? T
            case is Bool.Type: false as? T
            case is Int.Type: 0 as? T
            case is Int8.Type: Int8.zero as? T
            case is Int16.Type: Int16.zero as? T
            case is Int32.Type: Int32.zero as? T
            case is Int64.Type: Int64.zero as? T
            case is UInt.Type: UInt.zero as? T
            case is UInt8.Type: UInt8.zero as? T
            case is UInt16.Type: UInt16.zero as? T
            case is UInt32.Type: UInt32.zero as? T
            case is UInt64.Type: UInt64.zero as? T
            case is Float.Type: Float.zero as? T
            case is Double.Type: Double.zero as? T
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                case is Float16.Type: Float16.zero as? T
            #endif
            case is String.Type: "" as? T
            default: nil
        }
    }
#endif

enum SpyGetterEffectInput<P> {
    case automatic
    case ordered([Stub<P>.GetterEffect])
    case grouped([Stub<P>.ProtocolGetterEffects])
}

extension Stub {
    static func prewarmAutomaticPlan() throws {
        let _: RuntimeStubFactory.PreparedPlan<P> =
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    requirements: .automatic,
                    getterEffects: .automatic
                )
            )
    }

    static func prepareSpy(
        forwardingTo target: P,
        getterEffects: SpyGetterEffectInput<P>
    ) throws -> PreparedStub {
        try prepare {
            let plan: RuntimeStubFactory.PreparedPlan<P> =
                try RuntimeStubFactory.prepareForwardingStub(
                    to: target,
                    request: runtimePreparationRequest(
                        requirements: .automatic,
                        getterEffects: runtimeGetterEffects(getterEffects)
                    )
                )
            return plan
        }
    }

    static func prepare() throws -> PreparedStub {
        try prepare {
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    requirements: .automatic,
                    getterEffects: .automatic
                )
            )
        }
    }

    static func prepare(getterEffects: [GetterEffect]) throws -> PreparedStub {
        try prepare {
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    requirements: .automatic,
                    getterEffects: .flat(getterEffects.map(\.isThrowing))
                )
            )
        }
    }

    static func prepare(
        getterEffectGroups: [ProtocolGetterEffects]
    ) throws -> PreparedStub {
        try prepare {
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    requirements: .automatic,
                    getterEffects: .grouped(
                        getterEffectGroups.map {
                            RuntimeGetterEffectGroup(
                                declaringProtocol: $0.protocolType,
                                effects: $0.effects.map(\.isThrowing)
                            )
                        })
                )
            )
        }
    }

    static func prepare(requirements: [Requirement]) throws -> PreparedStub {
        try prepare {
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    requirements: .flat(requirements.map(\.runtimeSchema)),
                    getterEffects: .automatic
                )
            )
        }
    }

    static func prepare(
        requirementGroups: [ProtocolRequirements]
    ) throws -> PreparedStub {
        try prepare {
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    requirements: .grouped(
                        requirementGroups.map {
                            RuntimeExplicitRequirementGroup(
                                declaringProtocol: $0.protocolType,
                                requirements: $0.requirements.map(\.runtimeSchema)
                            )
                        }),
                    getterEffects: .automatic
                )
            )
        }
    }

    static func prepare(
        callerAssociatedTypeBindings: [AssociatedTypeBinding],
        requirements: [Requirement]
    ) throws -> PreparedStub {
        let requirementInput: RuntimeExplicitRequirementInput =
            requirements.isEmpty
            ? .automatic
            : .flat(requirements.map(\.runtimeSchema))
        return try prepare {
            try RuntimeStubFactory.prepareStub(
                runtimePreparationRequest(
                    callerAssociatedTypeBindings: callerAssociatedTypeBindings,
                    requirements: requirementInput,
                    getterEffects: .automatic
                )
            )
        }
    }

    static func prepareDummy() throws -> Dummy<P>.PreparedDummy {
        let protocolName = String(reflecting: P.self)
        let plan: RuntimeStubFactory.PreparedDummyPlan<P> =
            try RuntimeStubFactory
            .prepareDummy(runtimeShapeRequest())
        let endpoint = DummyInvocationEndpoint(
            typeDescription: protocolName,
            requirements: plan.requirements
        )
        let storage = try plan.materialize(
            endpoint: endpoint,
            protocolName: protocolName
        )
        return Dummy<P>.PreparedDummy(storage: storage)
    }

    private static func prepare(
        _ preparePlan: () throws -> RuntimeStubFactory.PreparedPlan<P>
    ) throws -> PreparedStub {
        let constructionStartedAt = ContinuousClock.now
        let plan = try preparePlan()
        let planPreparedAt = ContinuousClock.now
        let recorder = StubRecorder(
            methods: plan.methods,
            modifyDispatchDescriptors: plan.modifyDispatches,
            allowsForwardingFallback: plan.allowsForwardingFallback
        )
        let endpoint = StubRecorderInvocationEndpoint(recorder: recorder)
        let storage = try plan.materialize(
            endpoint: endpoint,
            protocolName: String(reflecting: P.self)
        )
        let materializedAt = ContinuousClock.now
        return PreparedStub(
            recorder: recorder,
            storage: storage,
            constructionPerformance: StubPerformanceDiagnostics.Construction(
                planPreparationDuration: constructionStartedAt.duration(
                    to: planPreparedAt
                ),
                materializationDuration: planPreparedAt.duration(
                    to: materializedAt
                )
            )
        )
    }

    private static func runtimePreparationRequest(
        callerAssociatedTypeBindings: [AssociatedTypeBinding] = [],
        requirements: RuntimeExplicitRequirementInput,
        getterEffects: RuntimeGetterEffectInput
    ) -> RuntimeStubPreparationRequest {
        RuntimeStubPreparationRequest(
            shape: runtimeShapeRequest(
                callerAssociatedTypeBindings: callerAssociatedTypeBindings
            ),
            requirements: requirements,
            getterEffects: getterEffects
        )
    }

    private static func runtimeShapeRequest(
        callerAssociatedTypeBindings: [AssociatedTypeBinding] = []
    ) -> RuntimeProtocolShapeRequest {
        RuntimeProtocolShapeRequest(
            protocolType: P.self,
            typeDescription: String(reflecting: P.self),
            callerAssociatedTypeBindings: callerAssociatedTypeBindings.map {
                RuntimeAssociatedTypeBindingRequest(
                    declaringProtocol: $0.protocolType,
                    name: $0.name,
                    type: $0.type
                )
            }
        )
    }

    private static func runtimeGetterEffects(
        _ input: SpyGetterEffectInput<P>
    ) -> RuntimeGetterEffectInput {
        switch input {
            case .automatic:
                .automatic
            case .ordered(let effects):
                .flat(effects.map(\.isThrowing))
            case .grouped(let groups):
                .grouped(
                    groups.map {
                        RuntimeGetterEffectGroup(
                            declaringProtocol: $0.protocolType,
                            effects: $0.effects.map(\.isThrowing)
                        )
                    })
        }
    }
}

final class DummyInvocationEndpoint: RuntimeInvocationEndpoint,
    @unchecked Sendable
{
    private let typeDescription: String
    private let requirements: [Int: String]

    init(
        typeDescription: String,
        requirements: [RuntimeDummyRequirement]
    ) {
        self.typeDescription = typeDescription
        self.requirements = Dictionary(
            uniqueKeysWithValues: requirements.map { ($0.slot, $0.description) }
        )
    }

    var invocationMode: RuntimeInvocationMode { .normal }

    func prepareDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimePreparedDispatch {
        _ = request.arguments
        rejectInvocation(at: request.slot)
    }

    func prepareAsyncDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimeAsyncDispatch {
        _ = request.arguments
        rejectInvocation(at: request.slot)
    }

    func completeForwardedInvocation(_ token: RuntimeInvocationToken) {
        _ = token
    }

    func completeInvocation(
        _ token: RuntimeInvocationToken,
        outcome: RuntimeInvocationOutcome
    ) {
        _ = token
        _ = outcome
    }

    func modifyDispatch(
        forGetterSlot getterSlot: Int
    ) -> RuntimeModifyDispatch? {
        _ = getterSlot
        return nil
    }

    func rejectInvocation(at slot: Int) -> Never {
        fatalError(rejectionMessage(slot: slot))
    }

    func methodName(at slot: Int) -> String {
        requirements[slot] ?? "unknown requirement at dispatch slot \(slot)"
    }

    func recordingAccessorResult(at slot: Int) -> Any {
        rejectInvocation(at: slot)
    }

    func dispatchTyped<Result>(
        _ request: RuntimeInvocationRequest,
        as resultType: Result.Type
    ) throws -> Result {
        _ = request.arguments
        _ = resultType
        rejectInvocation(at: request.slot)
    }

    func runtimeResourcesDidPublish(_ resources: AnyObject) {
        _ = resources
    }

    func runtimePayload() -> AnyObject? { nil }

    func dependentResult(
        for result: Any,
        at slot: Int
    ) -> RuntimeDependentResult {
        _ = result
        rejectInvocation(at: slot)
    }

    func recordingResult(at slot: Int) -> RuntimeRecordingResult {
        rejectInvocation(at: slot)
    }

    func rejectionMessage(slot: Int) -> String {
        let requirementDescription =
            requirements[slot]
            ?? "unknown requirement at dispatch slot \(slot)"
        return "[TestDoubles] Dummy<\(typeDescription)> was invoked through \(requirementDescription). "
            + "A dummy may only be passed to code paths that do not use it. If this invocation is "
            + "expected, replace the dummy with `Stub`, `ManualStub`, or a hand-written fake."
    }
}

/// Runs a runtime test-double construction operation while preserving the
/// public `StubError` failure contract.
func withStubConstructionError<Result>(
    for protocolType: Any.Type,
    _ operation: () throws -> Result
) throws(StubError) -> Result {
    #if TESTDOUBLES_RUNTIME_STUBS
        do {
            return try operation()
        } catch let error as StubError {
            throw error
        } catch let error as RuntimeConstructionError {
            throw StubError(error)
        } catch {
            unexpectedConstructionError(error, for: protocolType)
        }
    #else
        do {
            return try operation()
        } catch let error as StubError {
            throw error
        } catch {
            unexpectedConstructionError(error, for: protocolType)
        }
    #endif
}

private func unexpectedConstructionError(
    _ error: any Error,
    for protocolType: Any.Type
) -> Never {
    preconditionFailure(
        "[TestDoubles] Construction for '\(String(reflecting: protocolType))' "
            + "threw unexpected internal error type "
            + "'\(String(reflecting: Swift.type(of: error)))': \(error)"
    )
}

enum TestDoubleConstructionKind: String {
    case dummy
    case spy
    case stub
}

func constructTestDoubleOrFail<Result>(
    _ kind: TestDoubleConstructionKind,
    for protocolType: Any.Type,
    _ operation: () throws(StubError) -> Result
) -> Result {
    do {
        return try operation()
    } catch {
        fatalError(
            "[TestDoubles] Could not construct a \(kind.rawValue) for "
                + "'\(String(reflecting: protocolType))': \(error)"
        )
    }
}

#if TESTDOUBLES_RUNTIME_STUBS
    extension StubError {
        init(_ runtimeError: RuntimeConstructionError) {
            switch runtimeError {
                case .typeIsNotProtocol(let typeDescription):
                    self = .typeIsNotProtocol(typeDescription: typeDescription)
                case .compositionRequiresGroupedRequirements(let typeDescription):
                    self = .compositionRequiresGroupedRequirements(typeDescription: typeDescription)
                case .compositionRequiresGroupedGetterEffects(let typeDescription):
                    self = .compositionRequiresGroupedGetterEffects(typeDescription: typeDescription)
                case .invalidProtocolRequirementGroup(let typeDescription):
                    self = .invalidProtocolRequirementGroup(typeDescription: typeDescription)
                case .missingProtocolRequirementGroup(let protocolName):
                    self = .missingProtocolRequirementGroup(protocolName: protocolName)
                case .duplicateProtocolRequirementGroup(let protocolName):
                    self = .duplicateProtocolRequirementGroup(protocolName: protocolName)
                case .foreignProtocolRequirementGroup(let protocolName, let typeDescription):
                    self = .foreignProtocolRequirementGroup(
                        protocolName: protocolName,
                        typeDescription: typeDescription
                    )
                case .invalidProtocolGetterEffectGroup(let typeDescription):
                    self = .invalidProtocolGetterEffectGroup(typeDescription: typeDescription)
                case .missingProtocolGetterEffectGroup(let protocolName):
                    self = .missingProtocolGetterEffectGroup(protocolName: protocolName)
                case .duplicateProtocolGetterEffectGroup(let protocolName):
                    self = .duplicateProtocolGetterEffectGroup(protocolName: protocolName)
                case .foreignProtocolGetterEffectGroup(let protocolName, let typeDescription):
                    self = .foreignProtocolGetterEffectGroup(
                        protocolName: protocolName,
                        typeDescription: typeDescription
                    )
                case .getterEffectCountMismatch(let protocolName, let expected, let actual):
                    self = .getterEffectCountMismatch(
                        protocolName: protocolName,
                        expected: expected,
                        actual: actual
                    )
                case .unsupportedTypeKind(let typeName):
                    self = .unsupportedTypeKind(typeName: typeName)
                case .unsupportedProtocolShape(let protocolName, let reason):
                    self = .unsupportedProtocolShape(protocolName: protocolName, reason: reason)
                case .noConformanceFound(let protocolName):
                    self = .noConformanceFound(protocolName: protocolName)
                case .signatureDiscoveryFailed(let protocolName, let requirementIndex, let details):
                    self = .signatureDiscoveryFailed(
                        protocolName: protocolName,
                        requirementIndex: requirementIndex,
                        details: details
                    )
                case .requirementCountMismatch(let protocolName, let expected, let actual):
                    self = .requirementCountMismatch(
                        protocolName: protocolName,
                        expected: expected,
                        actual: actual
                    )
                case .requirementMismatch(let protocolName, let requirementIndex, let expected, let actual):
                    self = .requirementMismatch(
                        protocolName: protocolName,
                        requirementIndex: requirementIndex,
                        expected: expected,
                        actual: actual
                    )
                case .forwardingUnsupported(let protocolName, let reason):
                    self = .unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: Self.forwardingDiagnostic(reason)
                    )
                case .trampolineAllocationFailed(let requirementIndex):
                    self = .trampolineAllocationFailed(requirementIndex: requirementIndex)
            }
        }

        private static func forwardingDiagnostic(
            _ reason: RuntimeForwardingUnsupportedReason
        ) -> String {
            switch reason {
                case .pairedLegacyReadAndYieldingBorrow:
                    return "Forwarding Spy does not yet support Swift 6.4's paired legacy read and yielding-borrow witnesses. Use a Stub or a hand-written spy."
                case .nonInstanceRequirement(let index):
                    return "Forwarding Spy supports instance requirements only; requirement \(index) uses a metatype receiver."
                case .simd(let index):
                    return "Forwarding Spy does not yet support SIMD arguments or results in requirement \(index)."
                case .functionValues(let index):
                    return "Forwarding Spy does not yet support function-valued arguments or results in requirement \(index)."
                case .outgoingStackWords(let index, let limit):
                    return "Forwarding Spy requirement \(index) needs more outgoing stack transport than \(limit) words support. Use fewer arguments or a hand-written spy."
                case .dynamicSelfResult(let index):
                    return "Forwarding Spy does not yet support dynamic Self results in requirement \(index)."
                case .selfArguments(let index):
                    return "Forwarding Spy does not support direct or Optional Self arguments in requirement \(index). Use an automatic Stub or a hand-written spy."
                case .hiddenArguments(let index):
                    return "Forwarding Spy requirement \(index) uses stack arguments or leaves no registers for its target metadata and witness table. Use fewer arguments or a hand-written spy."
            }
        }
    }
#endif
