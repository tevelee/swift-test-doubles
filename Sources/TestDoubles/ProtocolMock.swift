import Echo

/// Describes a protocol requirement for thunk matching.
public struct MethodDescriptor: Sendable {
    public let name: String
    public let signature: MethodSignature
    public let index: Int

    public init(name: String, signature: MethodSignature, index: Int) {
        self.name = name
        self.signature = signature
        self.index = index
    }

    public static func getter(_ name: String, type: String, at index: Int) -> MethodDescriptor {
        MethodDescriptor(name: name, signature: .getter(type), index: index)
    }

    public static func method(_ name: String, args: [String], returns ret: String, at index: Int) -> MethodDescriptor {
        MethodDescriptor(name: name, signature: .init(args: args, ret: ret), index: index)
    }
}

/// A runtime mock for any protocol. No macros, no source access needed.
///
/// Two ways to create:
///
/// **Auto-discovery (no real instance needed):**
/// ```swift
/// let mock = ProtocolMock(forProtocolNamed: "UserService", methods: [
///     .method("fetch(id:)", args: ["Int"], returns: "String", at: 0),
///     .getter("count", type: "Int", at: 1),
/// ])
/// ```
///
/// **Cloning a real instance:**
/// ```swift
/// var real: any UserService = RealService()
/// let mock = ProtocolMock(cloning: &real, methods: [...])
/// ```
public class ProtocolMock {
    public let recorder = StubRecorder()
    private let wtAllocation: UnsafeMutableRawPointer
    private let containerBytes: ExistentialContainer

    /// Creates a mock by auto-discovering a conformance from the binary.
    /// No real instance needed — Echo scans the binary for any type
    /// conforming to the named protocol.
    ///
    /// - Parameters:
    ///   - protocolName: Name of the protocol (e.g., "UserService")
    ///   - methods: Descriptor for each protocol requirement
    public init(forProtocolNamed protocolName: String, methods: [MethodDescriptor]) {
        guard let conformance = findConformance(toProtocolNamed: protocolName) else {
            fatalError("No conformance found for protocol '\(protocolName)' in the binary")
        }

        let proto = conformance.protocol
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements

        // Get witness table from conformance descriptor
        let sourceWT = conformance.witnessTablePattern

        // Clone witness table
        let tableSize = totalWords * wordSize
        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: tableSize, alignment: wordSize)
        clonedWT.copyMemory(from: sourceWT.ptr, byteCount: tableSize)
        self.wtAllocation = clonedWT

        // Patch each slot
        for method in methods {
            guard let thunkPtr = ThunkLibrary.thunk(for: method.signature, slot: method.index) else {
                fatalError("""
                No pre-compiled thunk for '\(method.name)' \
                (signature: \(method.signature), slot: \(method.index)).
                """)
            }
            (clonedWT + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            recorder.setName(method.name, for: method.index)
        }

        MockRegistry.register(recorder, for: UnsafeRawPointer(clonedWT))

        // Build existential container with:
        // - Zero-initialized value buffer (3 words)
        // - Type metadata from the discovered conforming type
        // - Our patched witness table
        let typeDesc = conformance.contextDescriptor!
        let typeMetaPtr: UnsafeRawPointer
        if let structDesc = typeDesc as? StructDescriptor {
            typeMetaPtr = unsafeBitCast(structDesc.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let classDesc = typeDesc as? ClassDescriptor {
            typeMetaPtr = unsafeBitCast(classDesc.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let enumDesc = typeDesc as? EnumDescriptor {
            typeMetaPtr = unsafeBitCast(enumDesc.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else {
            fatalError("Unsupported type descriptor kind for '\(typeDesc.name)'")
        }

        var base = AnyExistentialContainer(type: unsafeBitCast(typeMetaPtr, to: Any.Type.self))
        // Value buffer stays zero-initialized (our thunks don't read self)
        self.containerBytes = ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: UnsafeRawPointer(clonedWT))
        )
    }

    /// Creates a mock by cloning a real conformance's witness table.
    ///
    /// - Parameters:
    ///   - realValuePtr: Raw pointer to the real `any Protocol` value
    ///   - methods: Descriptor for each protocol requirement
    public init(realValuePtr: UnsafeRawPointer, methods: [MethodDescriptor]) {
        let realContainer = realValuePtr.load(as: ExistentialContainer.self)
        let proto = realContainer.witnessTable.conformanceDescriptor.protocol
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements
        let tableSize = totalWords * wordSize

        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: tableSize, alignment: wordSize)
        clonedWT.copyMemory(from: realContainer.witnessTable.ptr, byteCount: tableSize)
        self.wtAllocation = clonedWT

        for method in methods {
            guard let thunkPtr = ThunkLibrary.thunk(for: method.signature, slot: method.index) else {
                fatalError("""
                No pre-compiled thunk for '\(method.name)' \
                (signature: \(method.signature), slot: \(method.index)).
                """)
            }
            (clonedWT + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            recorder.setName(method.name, for: method.index)
        }

        MockRegistry.register(recorder, for: UnsafeRawPointer(clonedWT))

        var container = realContainer
        container.witnessTable = WitnessTable(ptr: UnsafeRawPointer(clonedWT))
        self.containerBytes = container
    }

    deinit {
        MockRegistry.remove(for: UnsafeRawPointer(wtAllocation))
        wtAllocation.deallocate()
    }

    /// Write the mock's existential container into an `any Protocol` variable.
    public func write(to pointer: UnsafeMutableRawPointer) {
        pointer.storeBytes(of: containerBytes, as: ExistentialContainer.self)
    }
}

// MARK: - Convenience

extension ProtocolMock {
    public convenience init(cloning realValue: UnsafeMutableRawPointer, methods: [MethodDescriptor]) {
        self.init(realValuePtr: UnsafeRawPointer(realValue), methods: methods)
    }

    /// Write the mock into a typed existential variable.
    public func write<T>(to existential: inout T) {
        withUnsafeMutablePointer(to: &existential) { ptr in
            write(to: UnsafeMutableRawPointer(ptr))
        }
    }
}
