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
        guard concreteSIMDRegisterByteCount(for: value.type) == 16 else {
            return "Only complete 128-bit lane payloads with one identical arm64/x86_64 vector-register shape are supported."
        }
        guard case .aggregate(let parts) = value.layout,
            parts.count == 1,
            parts[0].register == .fp,
            parts[0].offset == 0,
            parts[0].byteCount == 16
        else {
            return "Its runtime ABI classification is not one 128-bit vector register."
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
            guard locations.count == 1,
                case .vectorRegister = locations[0].storage
            else {
                return "Its vector argument spills outside the captured register bank on \(architecture)."
            }
        }
    }
    return nil
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
