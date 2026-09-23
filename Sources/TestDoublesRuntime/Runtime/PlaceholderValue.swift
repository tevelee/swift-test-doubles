import Echo
import EchoRuntimeSupport
import Foundation

/// Supplies a complete value for a type that structural synthesis cannot
/// initialize itself, such as a class or an opaque framework value.
///
/// The returned value must have exactly the requested dynamic type. Returning
/// `nil` keeps the type unsupported.
package typealias PlaceholderLeafValue = (Any.Type) -> Any?

/// Creates valid placeholder values for matcher recording and runtime fallback returns.
package enum PlaceholderValue {
    /// Creates a placeholder of `type`, or returns `nil` when the type cannot be synthesized safely.
    package static func make<T>(
        _ type: T.Type = T.self,
        leafValue: PlaceholderLeafValue? = nil
    ) -> T? {
        make(type, includingDummyValues: false, leafValue: leafValue)
    }

    static func make<T>(
        _ type: T.Type,
        includingDummyValues: Bool,
        leafValue: PlaceholderLeafValue? = nil
    ) -> T? {
        let storage = ValueStorage.allocate(for: type)
        var visited: Set<UInt> = []
        guard
            let plan = initializationPlan(
                for: type,
                visited: &visited,
                includingDummyValues: includingDummyValues,
                leafValue: leafValue
            )
        else {
            storage.deallocate()
            return nil
        }
        storage.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: ValueStorage.byteCount(for: type)
        )
        execute(plan, at: storage)
        defer { storage.deallocate() }

        // `initialize(type:at:)` constructs a valid `T`. Move that initialized
        // value out so nontrivial ownership is transferred to the return value.
        return storage.assumingMemoryBound(to: T.self).move()
    }

    private static let recordingLeafLock = NSLock()
    nonisolated(unsafe) private static var installedRecordingLeafValue: (@Sendable (Any.Type) -> Any?)?

    /// Installs the supplier that runtime recording consults for nested
    /// values structural synthesis cannot initialize, such as the semantic
    /// target's built-in placeholder catalog.
    package static func installRecordingLeafValue(
        _ supplier: @escaping @Sendable (Any.Type) -> Any?
    ) {
        recordingLeafLock.withLock { installedRecordingLeafValue = supplier }
    }

    private static var recordingLeafValue: PlaceholderLeafValue? {
        recordingLeafLock.lock()
        let supplier = installedRecordingLeafValue
        recordingLeafLock.unlock()
        guard let supplier else { return nil }
        return { type in supplier(type) }
    }

    /// Initializes a placeholder at `destination` when `type` can be synthesized safely.
    package static func initialize(type: Any.Type, at destination: UnsafeMutableRawPointer) -> Bool {
        var visited: Set<UInt> = []
        guard
            let plan = initializationPlan(
                for: type,
                visited: &visited,
                includingDummyValues: false,
                leafValue: recordingLeafValue
            )
        else {
            return false
        }
        destination.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: ValueStorage.byteCount(for: type)
        )
        execute(plan, at: destination)
        return true
    }

    /// Returns whether `type` can be initialized as a valid placeholder.
    package static func canInitialize(type: Any.Type) -> Bool {
        var visited: Set<UInt> = []
        return initializationPlan(
            for: type,
            visited: &visited,
            includingDummyValues: false,
            leafValue: recordingLeafValue
        ) != nil
    }

    private indirect enum InitializationPlan {
        case scalar(ScalarInitialization)
        case suppliedValue(Any, Any.Type)
        case zeroed
        case collection(CollectionKind, Any.Type)
        case dummyFunction(DummyValue.FunctionPlan)
        case emptyEnum(Any.Type)
        case opaqueExistential(OpaqueExistentialKind)
        case payloadEnum(Any.Type, tag: UInt32, payload: InitializationPlan)
        case aggregate([AggregateElement])
        case metatype(UInt)
    }

    private enum ScalarInitialization {
        case int
        case int8
        case int16
        case int32
        case int64
        case uint
        case uint8
        case uint16
        case uint32
        case uint64
        case bool
        case float
        case double
        #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
            case float16
        #endif
        case string
    }

    private enum OpaqueExistentialKind {
        case any
        case anyObject
    }

    private struct AggregateElement {
        let offset: Int
        let plan: InitializationPlan
    }

    /// Builds the complete placeholder operation before any destination memory
    /// is initialized, so support checks and initialization cannot drift apart.
    ///
    /// A type that structural synthesis rejects is offered to `leafValue`, at
    /// every depth, before the whole plan fails.
    private static func initializationPlan(
        for type: Any.Type,
        visited: inout Set<UInt>,
        includingDummyValues: Bool,
        leafValue: PlaceholderLeafValue? = nil
    ) -> InitializationPlan? {
        if let plan = structuralPlan(
            for: type,
            visited: &visited,
            includingDummyValues: includingDummyValues,
            leafValue: leafValue
        ) {
            return plan
        }
        guard let leafValue, let value = leafValue(type) else { return nil }
        // The value is copied into storage laid out for `type`, so it must
        // cast to exactly that static type.
        func casts<Value>(_: Value.Type) -> Bool { value is Value }
        guard _openExistential(type, do: casts) else { return nil }
        return .suppliedValue(value, type)
    }

    private static func structuralPlan(
        for type: Any.Type,
        visited: inout Set<UInt>,
        includingDummyValues: Bool,
        leafValue: PlaceholderLeafValue?
    ) -> InitializationPlan? {
        if let scalar = scalarInitialization(for: type) {
            return .scalar(scalar)
        }
        if includingDummyValues, type == Any.self {
            return .opaqueExistential(.any)
        }
        if includingDummyValues, type == AnyObject.self {
            return .opaqueExistential(.anyObject)
        }
        let metadata = reflect(type)
        if includingDummyValues,
            let function = DummyValue.functionPlan(for: type)
        {
            return .dummyFunction(function)
        }
        if let kind = collectionKind(of: metadata) {
            return .collection(kind, type)
        }
        if let enumMetadata = metadata as? EnumMetadata {
            // An imported C enum is laid out as its raw integer and has no
            // Swift enum witnesses; every bit pattern, including zero, is a
            // valid value.
            if isImportedFromC(enumMetadata.descriptor) {
                return .zeroed
            }
            if enumMetadata.descriptor.numEmptyCases > 0 {
                return .emptyEnum(type)
            }
            guard includingDummyValues else { return nil }

            let key = UInt(bitPattern: enumMetadata.ptr)
            guard visited.insert(key).inserted else { return nil }
            defer { visited.remove(key) }

            let payloadCount = enumMetadata.descriptor.numPayloadCases
            let records = enumMetadata.descriptor.fields.records
            guard payloadCount > 0, records.count >= payloadCount else {
                return nil
            }
            for (index, record) in records.prefix(payloadCount).enumerated() {
                guard record.flags.isIndirectCase == false,
                    record.hasMangledTypeName,
                    let payloadType = resolvedFieldType(
                        record.mangledTypeName,
                        in: enumMetadata
                    ),
                    let payload = initializationPlan(
                        for: payloadType,
                        visited: &visited,
                        includingDummyValues: includingDummyValues,
                        leafValue: leafValue
                    )
                else {
                    continue
                }
                return .payloadEnum(
                    type,
                    tag: UInt32(index),
                    payload: payload
                )
            }
            return nil
        }
        if let tupleMetadata = metadata as? TupleMetadata {
            var elements: [AggregateElement] = []
            for element in tupleMetadata.elements {
                guard
                    let plan = initializationPlan(
                        for: element.type,
                        visited: &visited,
                        includingDummyValues: includingDummyValues,
                        leafValue: leafValue
                    )
                else {
                    return nil
                }
                elements.append(AggregateElement(offset: element.offset, plan: plan))
            }
            return .aggregate(elements)
        }
        if let metatypeMetadata = metadata as? MetatypeMetadata {
            return .metatype(
                UInt(
                    bitPattern: unsafeBitCast(
                        metatypeMetadata.instanceType,
                        to: UnsafeRawPointer.self
                    )))
        }
        if let metatypeMetadata = metadata as? ExistentialMetatypeMetadata {
            return .metatype(
                UInt(
                    bitPattern: unsafeBitCast(
                        metatypeMetadata.instanceType,
                        to: UnsafeRawPointer.self
                    )))
        }
        guard let structMetadata = metadata as? StructMetadata else {
            return nil
        }
        let key = UInt(bitPattern: structMetadata.ptr)
        guard visited.insert(key).inserted else {
            return nil
        }
        defer { visited.remove(key) }

        let fields = structMetadata.descriptor.fields.records
        let offsets = structMetadata.fieldOffsets
        guard fields.count == offsets.count else {
            return nil
        }
        var elements: [AggregateElement] = []
        for (field, offset) in zip(fields, offsets) {
            guard field.hasMangledTypeName,
                let fieldType = resolvedFieldType(
                    field.mangledTypeName,
                    in: structMetadata
                ),
                let plan = initializationPlan(
                    for: fieldType,
                    visited: &visited,
                    includingDummyValues: includingDummyValues,
                    leafValue: leafValue
                )
            else {
                return nil
            }
            elements.append(AggregateElement(offset: offset, plan: plan))
        }
        return .aggregate(elements)
    }

    private static func execute(
        _ plan: InitializationPlan,
        at destination: UnsafeMutableRawPointer
    ) {
        switch plan {
            case .scalar(let scalar):
                initializeScalar(scalar, at: destination)
            case .suppliedValue(let value, let type):
                initializeSupplied(value, as: type, at: destination)
            case .zeroed:
                // Storage is zero-filled before any plan executes.
                break
            case .collection(let kind, let type):
                initializeEmptyCollection(kind, type: type, at: destination)
            case .dummyFunction(let plan):
                DummyValue.initialize(plan, at: destination)
            case .emptyEnum(let type):
                guard let metadata = reflect(type) as? EnumMetadata else {
                    preconditionFailure("[TestDoubles] Missing enum metadata for \(type).")
                }
                metadata.enumVwt.destructiveInjectEnumTag(
                    for: destination,
                    tag: UInt32(metadata.descriptor.numPayloadCases)
                )
            case .opaqueExistential(.any):
                initialize(() as Any, at: destination)
            case .opaqueExistential(.anyObject):
                initialize(OpaquePlaceholderObject() as AnyObject, at: destination)
            case .payloadEnum(let type, let tag, let payload):
                guard let metadata = reflect(type) as? EnumMetadata else {
                    preconditionFailure("[TestDoubles] Missing enum metadata for \(type).")
                }
                execute(payload, at: destination)
                metadata.enumVwt.destructiveInjectEnumTag(
                    for: destination,
                    tag: tag
                )
            case .aggregate(let elements):
                for element in elements {
                    execute(element.plan, at: destination + element.offset)
                }
            case .metatype(let pointer):
                destination.storeBytes(of: pointer, as: UInt.self)
        }
    }

    private static func initializeScalar(
        _ scalar: ScalarInitialization,
        at destination: UnsafeMutableRawPointer
    ) {
        switch scalar {
            case .int:
                initialize(0 as Int, at: destination)
            case .int8:
                initialize(0 as Int8, at: destination)
            case .int16:
                initialize(0 as Int16, at: destination)
            case .int32:
                initialize(0 as Int32, at: destination)
            case .int64:
                initialize(0 as Int64, at: destination)
            case .uint:
                initialize(0 as UInt, at: destination)
            case .uint8:
                initialize(0 as UInt8, at: destination)
            case .uint16:
                initialize(0 as UInt16, at: destination)
            case .uint32:
                initialize(0 as UInt32, at: destination)
            case .uint64:
                initialize(0 as UInt64, at: destination)
            case .bool:
                initialize(false, at: destination)
            case .float:
                initialize(0 as Float, at: destination)
            case .double:
                initialize(0 as Double, at: destination)
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                case .float16:
                    initialize(0 as Float16, at: destination)
            #endif
            case .string:
                initialize("", at: destination)
        }
    }

    private static func scalarInitialization(
        for type: Any.Type
    ) -> ScalarInitialization? {
        switch type {
            case is Int.Type: .int
            case is Int8.Type: .int8
            case is Int16.Type: .int16
            case is Int32.Type: .int32
            case is Int64.Type: .int64
            case is UInt.Type: .uint
            case is UInt8.Type: .uint8
            case is UInt16.Type: .uint16
            case is UInt32.Type: .uint32
            case is UInt64.Type: .uint64
            case is Bool.Type: .bool
            case is Float.Type: .float
            case is Double.Type: .double
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                case is Float16.Type: .float16
            #endif
            case is String.Type: .string
            default: nil
        }
    }

    // MARK: - Empty collection placeholders

    private enum CollectionKind {
        case array
        case set
        case dictionary
    }

    private static let arrayDescriptor = UInt(
        bitPattern: reflectStruct([Int].self)!.descriptor.ptr
    )
    private static let setDescriptor = UInt(
        bitPattern: reflectStruct(Set<Int>.self)!.descriptor.ptr
    )
    private static let dictionaryDescriptor = UInt(
        bitPattern: reflectStruct([Int: Int].self)!.descriptor.ptr
    )

    private static func collectionKind(of metadata: Metadata) -> CollectionKind? {
        guard let structMetadata = metadata as? StructMetadata else { return nil }
        switch UInt(bitPattern: structMetadata.descriptor.ptr) {
            case arrayDescriptor: return .array
            case setDescriptor: return .set
            case dictionaryDescriptor: return .dictionary
            default: return nil
        }
    }

    private static func initializeEmptyCollection(
        _ kind: CollectionKind,
        type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        guard let structMetadata = reflectStruct(type) else {
            preconditionFailure("[TestDoubles] Missing collection metadata for \(type).")
        }
        let genericTypes = structMetadata.genericTypes
        switch kind {
            case .array:
                func openElement<Element>(_: Element.Type) {
                    initialize([Element](), at: destination)
                }
                _openExistential(genericTypes[0], do: openElement)

            case .set:
                guard let element = genericTypes[0] as? any Hashable.Type else {
                    preconditionFailure(
                        "[TestDoubles] Set element \(genericTypes[0]) is not Hashable."
                    )
                }
                initializeEmptySet(of: element, at: destination)

            case .dictionary:
                guard let key = genericTypes[0] as? any Hashable.Type else {
                    preconditionFailure(
                        "[TestDoubles] Dictionary key \(genericTypes[0]) is not Hashable."
                    )
                }
                initializeEmptyDictionary(key: key, value: genericTypes[1], at: destination)
        }
    }

    private static func initializeEmptySet<Element: Hashable>(
        of _: Element.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        initialize(Set<Element>(), at: destination)
    }

    private static func initializeEmptyDictionary<Key: Hashable>(
        key _: Key.Type,
        value: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        func openValue<Value>(_: Value.Type) {
            initialize([Key: Value](), at: destination)
        }
        _openExistential(value, do: openValue)
    }

    /// Whether `type` is an enum imported from C, such as an `NS_ENUM`.
    package static func isImportedCEnum(_ type: Any.Type) -> Bool {
        guard let metadata = reflect(type) as? EnumMetadata else { return false }
        return isImportedFromC(metadata.descriptor)
    }

    private static func isImportedFromC(_ descriptor: ContextDescriptor) -> Bool {
        (descriptor.parent as? ModuleDescriptor)?.name == "__C"
    }

    private static func initializeSupplied(
        _ value: Any,
        as type: Any.Type,
        at destination: UnsafeMutableRawPointer
    ) {
        func open<Value>(_: Value.Type) {
            guard let typed = value as? Value else {
                preconditionFailure(
                    "[TestDoubles] Supplied placeholder \(Swift.type(of: value)) is not \(Value.self)."
                )
            }
            initialize(typed, at: destination)
        }
        _openExistential(type, do: open)
    }

    private static func initialize<T>(_ value: T, at destination: UnsafeMutableRawPointer) {
        var value = value
        withUnsafeMutablePointer(to: &value) {
            ValueOperations.initializeCopy(
                of: T.self,
                from: UnsafeRawPointer($0),
                to: destination
            )
        }
    }
}

private final class OpaquePlaceholderObject {}
