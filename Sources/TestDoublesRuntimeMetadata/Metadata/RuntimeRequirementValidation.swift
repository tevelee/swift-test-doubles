import Echo
import TestDoublesRuntimeSupport

/// Keeps ABI-facing validation inside the runtime target. The public target
/// retains only its stable diagnostic vocabulary and maps these failures at
/// its construction boundary.
package func runtimeIsFunctionType(_ type: Any.Type) -> Bool {
    reflect(type).kind == .function
}

package func runtimeSIMDUnsupportedReason(
    for method: MethodDescriptor
) -> String? {
    let values = method.arguments.map(\.value) + [method.result]
    let simdValues = values.filter { runtimeContainsSIMDStorage($0.type) }
    guard simdValues.isEmpty == false else { return nil }

    guard method.kind == .method, method.receiver == .instance else {
        return "The bounded vector-register path supports ordinary instance methods only."
    }
    guard method.isAsync == false else {
        return "Async continuation transport has not been proven for SIMD registers."
    }

    for value in simdValues {
        guard value.type is any SIMD.Type else {
            return "SIMD nested in an aggregate does not share the direct vector ABI."
        }
        guard value.dependency.isAssociatedTypeDependent == false else {
            return "Associated-dependent SIMD needs metadata-directed vector substitution."
        }
        guard let registerByteCount = concreteSIMDRegisterByteCount(for: value.type)
        else {
            return "Only complete 128-bit lane payloads made of whole 128-bit vector registers, with one identical arm64/x86_64 vector-register shape, are supported."
        }
        let expectedPartCount = registerByteCount / 16
        guard case .aggregate(let parts) = value.layout,
            parts.count == expectedPartCount,
            parts.enumerated().allSatisfy({ index, part in
                part.register == .fp && part.offset == index * 16 && part.byteCount == 16
            })
        else {
            return "Its runtime ABI classification is not a sequence of complete 128-bit vector registers."
        }
    }

    for architecture in [RuntimeArchitecture.arm64, .x86_64] {
        let transport = WitnessCallTransportPlan(
            method: method,
            architecture: architecture
        )
        for (argument, locations) in zip(
            method.arguments,
            transport.argumentLocations
        ) where argument.value.type is any SIMD.Type {
            guard
                locations.allSatisfy({
                    if case .vectorRegister = $0.storage { return true }
                    return false
                })
            else {
                return "Its vector argument spills outside the captured register bank on \(architecture)."
            }
        }
    }
    return nil
}

/// Whether `method` uses a requirement-level generic parameter in a shape the
/// runtime cannot yet transport, or `nil` otherwise. The metadata-register
/// interaction with `async` suspension and indirect typed-error transport is
/// unverified, so both fail closed.
package func runtimeMethodGenericParameterUnsupportedReason(
    for method: MethodDescriptor
) -> String? {
    let genericArguments = method.arguments.filter {
        if case .methodGenericParameter = $0.value.convention { return true }
        return false
    }
    guard genericArguments.isEmpty == false else { return nil }

    guard method.kind == .method, method.receiver == .instance else {
        return "Requirement-level generic parameters are supported only on ordinary instance methods."
    }
    guard method.isAsync == false else {
        return "Async continuation transport has not been proven for requirement-level generic parameters."
    }
    guard method.typedErrorType == nil else {
        return "Typed-throwing transport has not been proven alongside a requirement-level generic parameter."
    }
    guard genericArguments.allSatisfy({ $0.ownership == .borrowed }) else {
        return "Consuming requirement-level generic parameters need ownership-aware metadata transport."
    }

    let indices = genericArguments.compactMap { argument -> Int? in
        guard case .methodGenericParameter(let index) = argument.value.convention else {
            return nil
        }
        return index
    }
    guard indices.allSatisfy({ $0 >= 0 }) else {
        return "Requirement-level generic parameter indices must be non-negative."
    }
    let uniqueIndices = Set(indices)
    guard uniqueIndices.allSatisfy({ $0 < uniqueIndices.count }) else {
        return "Requirement-level generic parameter indices must form a dense sequence starting at 0."
    }
    return nil
}

/// Forwarding would need to replay the caller-supplied metadata register
/// into an outgoing call, which is unverified, so `Spy` always rejects it.
package func runtimeMethodGenericParameterForwardingUnsupportedReason(
    for method: MethodDescriptor
) -> String? {
    let usesGenericParameter = method.arguments.contains {
        if case .methodGenericParameter = $0.value.convention { return true }
        return false
    }
    guard usesGenericParameter else { return nil }
    return "Forwarding Spy does not support requirements with their own generic parameter."
}

package func validateExplicitRequirementsAgainstLinkedConformances(
    _ supplied: [MethodDescriptor],
    layout: ProtocolLayout,
    associatedTypeBindings: AssociatedTypeBindings
) throws {
    let requiresStrictDiscovery = associatedTypeBindings.isEmpty == false
    var witnessTables: [ProtocolLayout.DescriptorID: WitnessTable] = [:]
    for root in layout.roots {
        guard let conformance = Echo.findConformance(to: root) else { continue }
        var collected = witnessTables
        do {
            try LinkedWitnessTableGraph.collect(
                descriptor: root,
                witnessTable: conformance.witnessTablePattern,
                layout: layout,
                into: &collected
            )
            witnessTables = collected
        } catch {
            if requiresStrictDiscovery { throw error }
        }
    }

    let discoverableRequirements = layout.callableRequirements.filter {
        witnessTables[ProtocolLayout.DescriptorID($0.protocolDescriptor)] != nil
            || resilientRequirementSymbolName($0) != nil
    }
    for requirement in discoverableRequirements {
        let expected: MethodDescriptor
        do {
            guard
                let discovered = try discoverMethods(
                    witnessTables: witnessTables,
                    layout: layout,
                    requirements: [requirement],
                    associatedTypeBindings: associatedTypeBindings,
                    getterEffectPolicy: .explicitRequirementValidation
                ).first
            else {
                continue
            }
            expected = discovered
        } catch let error as RuntimeConstructionError {
            if case .unsupportedProtocolShape = error { throw error }
            if requiresStrictDiscovery { throw error }
            continue
        } catch {
            if requiresStrictDiscovery { throw error }
            continue
        }
        guard supplied.indices.contains(expected.index) else { continue }
        let actual = supplied[expected.index]
        guard actual.hasSameSignature(as: expected) == false else { continue }
        let protocolName = layout.callableRequirements[expected.index]
            .protocolDescriptor.name
        throw RuntimeConstructionError.requirementMismatch(
            protocolName: protocolName,
            requirementIndex: expected.index,
            expected: expected.signatureDescription,
            actual: actual.signatureDescription
        )
    }
}

private func runtimeContainsSIMDStorage(_ type: Any.Type) -> Bool {
    var visited: Set<UInt> = []
    return runtimeContainsSIMDStorage(type, visited: &visited)
}

private func runtimeContainsSIMDStorage(
    _ type: Any.Type,
    visited: inout Set<UInt>
) -> Bool {
    if type is any SIMD.Type {
        return true
    }
    let metadata = reflect(type)
    if let tupleMetadata = metadata as? TupleMetadata {
        return tupleMetadata.elements.contains {
            runtimeContainsSIMDStorage($0.type, visited: &visited)
        }
    }
    guard let structMetadata = reflectStruct(type) else {
        return false
    }
    let key = UInt(bitPattern: structMetadata.ptr)
    guard visited.insert(key).inserted else {
        return false
    }
    defer { visited.remove(key) }
    return structMetadata.descriptor.fields.records.contains { field in
        guard field.hasMangledTypeName,
            let fieldType = structMetadata.type(of: field.mangledTypeName)
        else {
            return false
        }
        return runtimeContainsSIMDStorage(fieldType, visited: &visited)
    }
}
