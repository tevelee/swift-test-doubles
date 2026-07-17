#if canImport(ObjectiveC)
    import Foundation
    import ObjectiveC
#endif

#if canImport(ObjectiveC)
    nonisolated(unsafe) private var superclassPayloadAssociationKey: UInt8 = 0
#endif

enum FabricatedConformanceTypeReference {
    case indirectTypeDescriptor(UnsafeRawPointer)
    case directObjectiveCClassName([UInt8])
}

struct FabricatedRuntimePlan {
    private enum Payload {
        case stub

        #if canImport(ObjectiveC)
            case superclass(NSObject.Type)
        #endif
    }

    let conformanceTypeReference: FabricatedConformanceTypeReference
    private let payload: Payload

    static func prepare(
        for representation: StubExistentialRepresentation,
        protocolName: String
    ) throws -> Self {
        switch representation {
            case .opaque, .classConstrained:
                return Self(
                    conformanceTypeReference: .indirectTypeDescriptor(
                        try payloadContextDescriptor()
                    ),
                    payload: .stub
                )

            case .superclassConstrained(let superclass):
                let conformanceTypeReference: FabricatedConformanceTypeReference
                if let descriptor = swift_getTypeContextDescriptor(superclass) {
                    conformanceTypeReference = .indirectTypeDescriptor(descriptor)
                } else {
                    #if canImport(ObjectiveC)
                        guard let objectType = superclass as? NSObject.Type else {
                            throw StubError.unsupportedProtocolShape(
                                protocolName: protocolName,
                                reason: "The superclass has neither a Swift type descriptor nor an Objective-C class identity."
                            )
                        }
                        let name = String(cString: class_getName(objectType))
                        conformanceTypeReference = .directObjectiveCClassName(
                            Array(name.utf8) + [0]
                        )
                    #else
                        throw StubError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "The superclass does not expose a Swift type context descriptor."
                        )
                    #endif
                }

                #if canImport(ObjectiveC)
                    guard let objectType = superclass as? NSObject.Type else {
                        throw StubError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "Superclass-constrained runtime test doubles require an NSObject-backed superclass."
                        )
                    }
                    return Self(
                        conformanceTypeReference: conformanceTypeReference,
                        payload: .superclass(objectType)
                    )
                #else
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Superclass-constrained runtime test doubles require the Objective-C runtime."
                    )
                #endif
        }
    }

    func makePayload(resources: StubResources) -> AnyObject {
        switch payload {
            case .stub:
                return StubPayload(resources: resources)

            #if canImport(ObjectiveC)
                case .superclass(let objectType):
                    let object = objectType.init()
                    objc_setAssociatedObject(
                        object,
                        &superclassPayloadAssociationKey,
                        StubPayload(resources: resources),
                        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    )
                    return object
            #endif
        }
    }
}

private func payloadContextDescriptor() throws -> UnsafeRawPointer {
    guard let descriptor = swift_getTypeContextDescriptor(StubPayload.self) else {
        throw StubError.unsupportedTypeKind(typeName: String(reflecting: StubPayload.self))
    }
    return descriptor
}

@_silgen_name("swift_getTypeContextDescriptor")
private func swift_getTypeContextDescriptor(_ type: Any.Type) -> UnsafeRawPointer?
