import Echo
import Foundation

/// Standard-library and concurrency types that are not `@frozen`.
///
/// Both libraries are built with library evolution, and their runtime
/// metadata carries the ABI module name `Swift`. Most of their commonly passed
/// types are `@frozen`, so the classifier lowers them from their reflected
/// layout. The types listed here are resilient instead: every client outside
/// the defining library passes and returns them indirectly, even when their
/// reflected storage is a single reference. Lowering, for example, an
/// `AsyncStream` result from its one-reference layout read the caller's
/// indirect-result address as the stream.
///
/// Names are qualified by their enclosing types. Each entry was checked
/// against the Swift 6.3 module interfaces.
private let nonFrozenStandardLibraryTypeNames: Set<String> = [
    // _Concurrency
    "AsyncStream",
    "AsyncStream.Continuation",
    "AsyncStream.Continuation.BufferingPolicy",
    "AsyncStream.Continuation.Termination",
    "AsyncStream.Continuation.YieldResult",
    "AsyncStream.Iterator",
    "AsyncThrowingStream",
    "AsyncThrowingStream.Continuation",
    "AsyncThrowingStream.Continuation.BufferingPolicy",
    "AsyncThrowingStream.Continuation.Termination",
    "AsyncThrowingStream.Continuation.YieldResult",
    "AsyncThrowingStream.Iterator",
    "CheckedContinuation",
    "ContinuousClock",
    "ContinuousClock.Instant",
    "SuspendingClock",
    "SuspendingClock.Instant",
    "TaskPriority",
    // Swift
    "CodingUserInfoKey",
    "CollectionDifference",
    "DecodingError",
    "EncodingError",
    "Mirror"
]

/// Whether `type` is, or stores inline, a value that is address-only for
/// every client: a non-`@frozen` standard-library value or an opaque
/// existential such as `Any`. Such a value is passed and returned indirectly
/// regardless of its reflected layout, including inside an `Optional`.
func storesAddressOnlyValue(_ type: Any.Type) -> Bool {
    var visited: Set<UInt> = []
    return storesAddressOnlyValue(type, visited: &visited)
}

private func storesAddressOnlyValue(
    _ type: Any.Type,
    visited: inout Set<UInt>
) -> Bool {
    let metadata = reflect(type)
    let key = UInt(bitPattern: metadata.ptr)
    guard visited.insert(key).inserted else { return false }

    // An opaque existential stores its value in an inline buffer or a box
    // chosen at runtime. Class-constrained and `Error` existentials are a
    // loadable reference instead.
    if let existential = metadata as? ExistentialMetadata {
        return existential.flags.isClassConstraint == false
            && existential.flags.specialProtocol != .error
    }

    if let tuple = metadata as? TupleMetadata {
        return tuple.elements.contains {
            storesAddressOnlyValue($0.type, visited: &visited)
        }
    }
    if let structure = metadata as? StructMetadata {
        if isNonFrozenStandardLibraryType(structure.descriptor) { return true }
        return structure.descriptor.fields.records.contains { field in
            guard field.hasMangledTypeName,
                let fieldType = resolvedFieldType(field.mangledTypeName, in: structure)
            else { return false }
            return storesAddressOnlyValue(fieldType, visited: &visited)
        }
    }
    if let enumeration = metadata as? EnumMetadata {
        if isNonFrozenStandardLibraryType(enumeration.descriptor) { return true }
        return enumeration.descriptor.fields.records.contains { record in
            // An indirect case stores a box reference, not the payload.
            guard record.flags.isIndirectCase == false,
                record.hasMangledTypeName,
                let payloadType = resolvedFieldType(record.mangledTypeName, in: enumeration)
            else { return false }
            return storesAddressOnlyValue(payloadType, visited: &visited)
        }
    }
    return false
}

private func isNonFrozenStandardLibraryType(_ descriptor: any TypeContextDescriptor) -> Bool {
    var components = [descriptor.name]
    var parent = descriptor.parent
    while let current = parent {
        if let module = current as? ModuleDescriptor {
            guard module.name == "Swift" else { return false }
            return nonFrozenStandardLibraryTypeNames.contains(
                components.reversed().joined(separator: ".")
            )
        }
        guard let enclosing = current as? any TypeContextDescriptor else { return false }
        components.append(enclosing.name)
        parent = enclosing.parent
    }
    return false
}

/// Memoizes ``storesAddressOnlyValue(_:)``, which walks stored fields, for
/// layouts computed on dispatch paths.
final class AddressOnlyValueCache: @unchecked Sendable {
    static let shared = AddressOnlyValueCache()

    private let lock = NSLock()
    private var results: [ObjectIdentifier: Bool] = [:]

    func stores(_ type: Any.Type) -> Bool {
        let key = ObjectIdentifier(type)
        if let cached = lock.withLock({ results[key] }) { return cached }
        let result = storesAddressOnlyValue(type)
        lock.withLock { results[key] = result }
        return result
    }
}
