import Echo

/// A validated view of an existential's root protocols and their inheritance
/// graphs.
///
/// Protocol witness-table slots are local to the descriptor that declares
/// them, while trampoline dispatch identifiers are dense across the complete
/// inheritance graph. Keeping both coordinates explicit prevents an inherited
/// requirement from accidentally being installed into the root table.
struct ProtocolLayout {
    struct DescriptorID: Hashable {
        let rawValue: UInt

        init(_ descriptor: ProtocolDescriptor) {
            rawValue = UInt(bitPattern: descriptor.ptr)
        }
    }

    struct BaseProtocol {
        let descriptor: ProtocolDescriptor
        let witnessIndex: Int
    }

    /// Stable identity for one getter requirement, scoped to its declaring
    /// protocol's witness table.
    struct GetterRequirementID: Hashable {
        let protocolID: DescriptorID
        let witnessIndex: Int

        init(protocolDescriptor: ProtocolDescriptor, witnessIndex: Int) {
            protocolID = DescriptorID(protocolDescriptor)
            self.witnessIndex = witnessIndex
        }
    }

    struct CallableRequirement {
        let protocolDescriptor: ProtocolDescriptor
        let witnessIndex: Int
        let dispatchIndex: Int
        let kind: StubRequirementKind
        let receiver: StubRequirementReceiver
    }

    struct AssociatedTypeRequirement {
        let protocolDescriptor: ProtocolDescriptor
        let witnessIndex: Int
        let name: String
        let usesReferenceABI: Bool
    }

    struct AssociatedConformanceRequirement {
        let protocolDescriptor: ProtocolDescriptor
        let witnessIndex: Int
        let associatedTypeName: String
        let constraint: ProtocolDescriptor
    }

    enum ModifyCoroutineABI: Equatable {
        /// The legacy `yield_once` witness is stored as a direct function.
        case yieldOnce
        /// `CoroutineAccessors` stores `modify2` as a `yield_once_2`
        /// descriptor with a caller-allocated frame.
        case yieldOnce2
    }

    /// A `_modify` witness and the ordinary getter/setter dispatch pair that
    /// provides its read and writeback behavior.
    struct ModifyCoroutineRequirement {
        let witnessIndex: Int
        let getterDispatchIndex: Int
        let setterDispatchIndex: Int
        let receiver: StubRequirementReceiver
        let abi: ModifyCoroutineABI
    }

    enum ReadCoroutineABI: Equatable {
        /// Swift 6.4's source-compatibility witness for the deprecated `read`
        /// spelling. Its `yield_once` ABI is not fabricated by TestDoubles.
        case yieldOnce
        /// Swift 6.3 `read2` and Swift 6.4 `yielding borrow` use the same
        /// `yield_once_2` descriptor ABI supported by the runtime trampoline.
        case yieldOnce2
    }

    /// A physical read witness and the getter-shaped recorder dispatch that
    /// supplies the value borrowed for the duration of the coroutine. Swift
    /// 6.4 maps its paired physical witnesses to one recorder dispatch.
    struct ReadCoroutineRequirement {
        let witnessIndex: Int
        let recorderDispatchIndex: Int
        let receiver: StubRequirementReceiver
        let abi: ReadCoroutineABI
    }

    struct Node {
        let descriptor: ProtocolDescriptor
        let baseProtocols: [BaseProtocol]
        let associatedTypes: [AssociatedTypeRequirement]
        let associatedConformances: [AssociatedConformanceRequirement]
        let callableRequirements: [CallableRequirement]
        let readCoroutineRequirements: [ReadCoroutineRequirement]
        let modifyCoroutineRequirements: [ModifyCoroutineRequirement]
    }

    /// Root protocols in canonical existential-metadata order.
    let roots: [ProtocolDescriptor]
    /// Nodes in base-first, depth-first, first-seen order.
    let nodes: [Node]
    /// Callable requirements in the same flattened order used by explicit APIs.
    let callableRequirements: [CallableRequirement]

    /// Protocols that directly declare one or more callable requirements.
    var declaringNodes: [Node] {
        nodes.filter { $0.callableRequirements.isEmpty == false }
    }

    /// Associated-type accessors in declaring-protocol order after the
    /// inheritance graph has been flattened.
    var associatedTypeRequirements: [AssociatedTypeRequirement] {
        nodes.flatMap(\.associatedTypes)
    }

    func node(for descriptor: ProtocolDescriptor) -> Node? {
        let identifier = DescriptorID(descriptor)
        return nodes.first { DescriptorID($0.descriptor) == identifier }
    }

    static func build(
        roots: [ProtocolDescriptor],
        allowsClassConstraint: Bool = false
    ) throws -> Self {
        var builder = Builder(
            contextName: roots.map(\.name).joined(separator: " & "),
            allowsClassConstraint: allowsClassConstraint
        )
        for root in roots {
            try builder.visit(root)
        }
        return Self(
            roots: roots,
            nodes: builder.nodes,
            callableRequirements: builder.callableRequirements
        )
    }
}
