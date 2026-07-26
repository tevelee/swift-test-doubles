import InternalRuntimeContract
import TestDoublesRuntime
import TestDoublesRuntimeMetadata

/// Test-only ABI assertions derived from the public semantic projection.
///
/// Production recording code deliberately cannot see this compatibility view:
/// raw layouts stay in `TestDoublesRuntime`. Runtime-focused tests use it only
/// while the existing integration fixtures are migrated into their own target.
extension RuntimeMethod {
    var argumentLayouts: [ABIClass] {
        arguments.map { abiLayout(for: $0.value, isReturn: false) }
    }

    var returnLayout: ABIClass {
        abiLayout(for: result, isReturn: true)
    }

    var typedErrorUsesIndirectResultSlot: Bool {
        guard let typedErrorType else { return false }
        let errorLayout = abiClass(for: typedErrorType, isReturn: true)
        let usesDependentErrorStorage = typedErrorDependency?.usesOpaqueTransport ?? false
        return usesDependentErrorStorage
            || isIndirect(returnLayout)
            || isIndirect(errorLayout)
    }

    private func abiLayout(
        for value: RuntimeValue,
        isReturn: Bool
    ) -> ABIClass {
        if value.dependency.usesOpaqueTransport {
            return .indirect
        }
        return switch value.convention {
            case .concrete:
                abiClass(for: value.type, isReturn: isReturn)
            case .associatedType:
                if case .referenceAssociatedType = value.dependency {
                    .integer(words: 1)
                } else {
                    .indirect
                }
            case .selfType, .optionalSelf:
                selfIsClassConstrained ? .integer(words: 1) : .indirect
        }
    }
}

extension RuntimeValue {
    var layout: ABIClass {
        if dependency.usesOpaqueTransport {
            return .indirect
        }
        return switch convention {
            case .concrete:
                abiClass(for: type)
            case .associatedType:
                if case .referenceAssociatedType = dependency {
                    .integer(words: 1)
                } else {
                    .indirect
                }
            case .selfType, .optionalSelf:
                .indirect
        }
    }
}

private func isIndirect(_ layout: ABIClass) -> Bool {
    if case .indirect = layout { true } else { false }
}

extension RuntimeValueDependency {
    fileprivate var usesOpaqueTransport: Bool {
        switch self {
            case .independent, .referenceAssociatedType:
                false
            case .associatedType:
                true
            case .optional(let wrapped):
                wrapped.usesOpaqueTransport
            case .array, .set, .dictionary, .genericClass:
                false
            case .result(let success, let failure):
                success.usesOpaqueTransport || failure.usesOpaqueTransport
        }
    }
}

extension RuntimeValueDependency {
    var usesOpaqueValueWitnessConvention: Bool {
        usesOpaqueTransport
    }
}
