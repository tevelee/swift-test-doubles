import Foundation
import InternalRuntimeContract

/// Successful preparation is immutable for one existential shape and
/// source-level schema. Failures are deliberately not cached so a dynamically
/// loaded image can still supply a conformance or symbol later.
enum PreparedStubPlanCache {
    struct Key: Hashable {
        struct AssociatedTypeBinding: Hashable {
            let declaringProtocol: ObjectIdentifier
            let name: String
            let type: ObjectIdentifier
        }

        struct GetterEffectGroup: Hashable {
            let declaringProtocol: ObjectIdentifier
            let effects: [GetterEffect]
        }

        struct GetterEffect: Hashable {
            let isThrowing: Bool
            let typedErrorType: ObjectIdentifier?
        }

        enum GetterEffects: Hashable {
            case automatic
            case flat([GetterEffect])
            case grouped([GetterEffectGroup])
        }

        indirect enum RequirementSource: Hashable {
            case concrete(ObjectIdentifier)
            case associatedType(String)
            case optional(RequirementSource)
            case array(RequirementSource)
            case set(RequirementSource)
            case dictionary(
                key: RequirementSource,
                value: RequirementSource
            )
            case result(
                success: RequirementSource,
                failure: RequirementSource
            )
            case selfType(isOptional: Bool)
            case methodGenericParameter(index: Int)
        }

        struct RequirementValue: Hashable {
            let source: RequirementSource
            let ownership: String?
        }

        struct Requirement: Hashable {
            let kind: RuntimeRequirementKind
            let arguments: [RequirementValue]
            let result: RequirementValue
            let typedErrorType: ObjectIdentifier?
            let typedErrorAssociatedTypeName: String?
            let isThrowing: Bool
            let isAsync: Bool
            let inferredFromSignature: Bool
            let erasedSelfType: ObjectIdentifier
            let erasedOptionalSelfType: ObjectIdentifier
        }

        struct RequirementGroup: Hashable {
            let declaringProtocol: ObjectIdentifier
            let requirements: [Requirement]
        }

        struct AutomaticRequirementAdapter: Hashable {
            let kind: RuntimeRequirementKind
            let argumentTypes: [ObjectIdentifier]
            let resultType: ObjectIdentifier
            let resultTransport: RuntimeAutomaticRequirementAdapter.ResultTransport
            let isThrowing: Bool
            let isAsync: Bool
            let functionType: ObjectIdentifier
            let invocationType: ObjectIdentifier
            let entryPoint: UInt
        }

        enum Requirements: Hashable {
            case automatic
            case flat([Requirement])
            case grouped([RequirementGroup])
        }

        let protocolType: ObjectIdentifier
        let associatedTypeBindings: [AssociatedTypeBinding]
        let requirements: Requirements
        let getterEffects: GetterEffects
        let automaticRequirementAdapters: [AutomaticRequirementAdapter]
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var plans: [Key: Any] = [:]
    }

    private static let storage = Storage()

    static func key(
        for request: RuntimeStubPreparationRequest
    ) -> Key? {
        let requirements: Key.Requirements
        switch request.requirements {
            case .automatic:
                requirements = .automatic
            case .flat(let schemas):
                guard let keys = requirementKeys(schemas) else {
                    return nil
                }
                requirements = .flat(keys)
            case .grouped(let groups):
                var keys: [Key.RequirementGroup] = []
                keys.reserveCapacity(groups.count)
                for group in groups {
                    guard
                        let requirements = requirementKeys(
                            group.requirements
                        )
                    else {
                        return nil
                    }
                    keys.append(
                        Key.RequirementGroup(
                            declaringProtocol: ObjectIdentifier(
                                group.declaringProtocol
                            ),
                            requirements: requirements
                        )
                    )
                }
                requirements = .grouped(keys)
        }
        let getterEffects: Key.GetterEffects =
            switch request.getterEffects {
                case .automatic:
                    .automatic
                case .flat(let effects):
                    .flat(effects.map(getterEffectKey))
                case .grouped(let groups):
                    .grouped(
                        groups.map {
                            Key.GetterEffectGroup(
                                declaringProtocol: ObjectIdentifier(
                                    $0.declaringProtocol
                                ),
                                effects: $0.effects.map(getterEffectKey)
                            )
                        })
            }
        var automaticRequirementAdapters: [Key.AutomaticRequirementAdapter] = []
        automaticRequirementAdapters.reserveCapacity(
            request.automaticRequirementAdapters.count
        )
        for adapter in request.automaticRequirementAdapters {
            guard
                let source = adapter.typedWitnessAdapter.payload(
                    as: RuntimeTypedWitnessAdapterSource.self
                )
            else {
                return nil
            }
            automaticRequirementAdapters.append(
                Key.AutomaticRequirementAdapter(
                    kind: adapter.kind,
                    argumentTypes: adapter.argumentTypes.map(ObjectIdentifier.init),
                    resultType: ObjectIdentifier(adapter.resultType),
                    resultTransport: adapter.resultTransport,
                    isThrowing: adapter.isThrowing,
                    isAsync: adapter.isAsync,
                    functionType: ObjectIdentifier(source.functionType),
                    invocationType: ObjectIdentifier(source.invocationType),
                    entryPoint: source.entryPoint
                )
            )
        }
        return Key(
            protocolType: ObjectIdentifier(request.shape.protocolType),
            associatedTypeBindings:
                request.shape.callerAssociatedTypeBindings.map {
                    Key.AssociatedTypeBinding(
                        declaringProtocol: ObjectIdentifier(
                            $0.declaringProtocol
                        ),
                        name: $0.name,
                        type: ObjectIdentifier($0.type)
                    )
                },
            requirements: requirements,
            getterEffects: getterEffects,
            automaticRequirementAdapters: automaticRequirementAdapters
        )
    }

    private static func getterEffectKey(
        _ effect: RuntimeGetterEffectHint
    ) -> Key.GetterEffect {
        Key.GetterEffect(
            isThrowing: effect.isThrowing,
            typedErrorType: effect.typedErrorType.map(ObjectIdentifier.init)
        )
    }

    private static func requirementKeys(
        _ schemas: [RuntimeExplicitRequirementSchema]
    ) -> [Key.Requirement]? {
        var keys: [Key.Requirement] = []
        keys.reserveCapacity(schemas.count)
        for schema in schemas {
            // The adapter token can close over an endpoint-specific factory.
            // Cache only schemas whose runtime plan is entirely structural.
            guard schema.typedWitnessAdapter == nil else { return nil }
            keys.append(
                Key.Requirement(
                    kind: schema.kind,
                    arguments: schema.arguments.map(requirementValueKey),
                    result: requirementValueKey(schema.result),
                    typedErrorType: schema.typedErrorType.map(
                        ObjectIdentifier.init
                    ),
                    typedErrorAssociatedTypeName:
                        schema.typedErrorAssociatedTypeName,
                    isThrowing: schema.isThrowing,
                    isAsync: schema.isAsync,
                    inferredFromSignature: schema.inferredFromSignature,
                    erasedSelfType: ObjectIdentifier(schema.erasedSelfType),
                    erasedOptionalSelfType: ObjectIdentifier(
                        schema.erasedOptionalSelfType
                    )
                )
            )
        }
        return keys
    }

    private static func requirementValueKey(
        _ value: RuntimeExplicitRequirementSchema.Value
    ) -> Key.RequirementValue {
        Key.RequirementValue(
            source: requirementSourceKey(value.source),
            ownership: value.ownership?.rawValue
        )
    }

    private static func requirementSourceKey(
        _ source: RuntimeExplicitRequirementSchema.Source
    ) -> Key.RequirementSource {
        switch source {
            case .concrete(let type):
                .concrete(ObjectIdentifier(type))
            case .associatedType(let name):
                .associatedType(name)
            case .optional(let wrapped):
                .optional(requirementSourceKey(wrapped))
            case .array(let element):
                .array(requirementSourceKey(element))
            case .set(let element):
                .set(requirementSourceKey(element))
            case .dictionary(let key, let value):
                .dictionary(
                    key: requirementSourceKey(key),
                    value: requirementSourceKey(value)
                )
            case .result(let success, let failure):
                .result(
                    success: requirementSourceKey(success),
                    failure: requirementSourceKey(failure)
                )
            case .selfType(let isOptional):
                .selfType(isOptional: isOptional)
            case .methodGenericParameter(let index):
                .methodGenericParameter(index: index)
        }
    }

    static func plan<P>(
        for key: Key
    ) -> RuntimeStubFactory.PreparedPlan<P>? {
        storage.lock.withLock {
            storage.plans[key] as? RuntimeStubFactory.PreparedPlan<P>
        }
    }

    static func insert<P>(
        _ plan: RuntimeStubFactory.PreparedPlan<P>,
        for key: Key
    ) -> RuntimeStubFactory.PreparedPlan<P> {
        storage.lock.withLock {
            if let existing =
                storage.plans[key] as? RuntimeStubFactory.PreparedPlan<P>
            {
                return existing
            }
            storage.plans[key] = plan
            return plan
        }
    }
}
