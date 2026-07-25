import Echo

/// A validated view of an existential's root protocols and their inheritance
/// graphs.
///
/// Protocol witness-table slots are local to the descriptor that declares
/// them, while trampoline dispatch identifiers are dense across the complete
/// inheritance graph. Keeping both coordinates explicit prevents an inherited
/// requirement from accidentally being installed into the root table.
package struct ProtocolLayout {
    package struct DescriptorID: Hashable {
        package let rawValue: UInt

        package init(_ descriptor: ProtocolDescriptor) {
            rawValue = UInt(bitPattern: descriptor.ptr)
        }
    }

    package struct BaseProtocol {
        package let descriptor: ProtocolDescriptor
        package let witnessIndex: Int
    }

    /// Stable identity for one getter requirement, scoped to its declaring
    /// protocol's witness table.
    package struct GetterRequirementID: Hashable {
        package let protocolID: DescriptorID
        package let witnessIndex: Int

        package init(protocolDescriptor: ProtocolDescriptor, witnessIndex: Int) {
            protocolID = DescriptorID(protocolDescriptor)
            self.witnessIndex = witnessIndex
        }
    }

    package struct CallableRequirement {
        package let protocolDescriptor: ProtocolDescriptor
        package let witnessIndex: Int
        package let dispatchIndex: Int
        package let kind: StubRequirementKind
        package let receiver: StubRequirementReceiver
    }

    package struct AssociatedTypeRequirement {
        package let protocolDescriptor: ProtocolDescriptor
        package let witnessIndex: Int
        package let name: String
        package let usesReferenceABI: Bool
    }

    package struct AssociatedConformanceRequirement {
        package let protocolDescriptor: ProtocolDescriptor
        package let witnessIndex: Int
        package let associatedTypeName: String
        package let constraint: ProtocolDescriptor
    }

    package enum ModifyCoroutineABI: Equatable {
        /// The legacy `yield_once` witness is stored as a direct function.
        case yieldOnce
        /// `CoroutineAccessors` stores `modify2` as a `yield_once_2`
        /// descriptor with a caller-allocated frame.
        case yieldOnce2
    }

    /// A `_modify` witness and the ordinary getter/setter dispatch pair that
    /// provides its read and writeback behavior.
    package struct ModifyCoroutineRequirement {
        package let witnessIndex: Int
        package let getterDispatchIndex: Int
        package let setterDispatchIndex: Int
        package let receiver: StubRequirementReceiver
        package let abi: ModifyCoroutineABI
    }

    package enum ReadCoroutineABI: Equatable {
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
    package struct ReadCoroutineRequirement {
        package let witnessIndex: Int
        package let recorderDispatchIndex: Int
        package let receiver: StubRequirementReceiver
        package let abi: ReadCoroutineABI
    }

    package struct Node {
        package let descriptor: ProtocolDescriptor
        package let baseProtocols: [BaseProtocol]
        package let associatedTypes: [AssociatedTypeRequirement]
        package let associatedConformances: [AssociatedConformanceRequirement]
        package let callableRequirements: [CallableRequirement]
        package let readCoroutineRequirements: [ReadCoroutineRequirement]
        package let modifyCoroutineRequirements: [ModifyCoroutineRequirement]
    }

    /// Root protocols in canonical existential-metadata order.
    package let roots: [ProtocolDescriptor]
    /// Nodes in base-first, depth-first, first-seen order.
    package let nodes: [Node]
    /// Callable requirements in the same flattened order used by explicit APIs.
    package let callableRequirements: [CallableRequirement]

    /// Protocols that directly declare one or more callable requirements.
    package var declaringNodes: [Node] {
        nodes.filter { $0.callableRequirements.isEmpty == false }
    }

    /// Associated-type accessors in declaring-protocol order after the
    /// inheritance graph has been flattened.
    package var associatedTypeRequirements: [AssociatedTypeRequirement] {
        nodes.flatMap(\.associatedTypes)
    }

    package func node(for descriptor: ProtocolDescriptor) -> Node? {
        let identifier = DescriptorID(descriptor)
        return nodes.first { DescriptorID($0.descriptor) == identifier }
    }

    package static func build(
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
