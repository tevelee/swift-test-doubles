import CTestDoublesTrampoline
import Echo

protocol ProtocolForwarding: AnyObject, Sendable {
    func forward(_ method: MethodDescriptor, frame: TrampolineCallFrame)
    func makeReadState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any ReadCoroutineForwardingState
    func makeAsyncState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any AsyncTrampolineDispatchState
}

/// Owns a concrete protocol existential at a stable address so its projected
/// value and witness tables remain valid for every forwarded call.
final class ForwardingTarget<P>: @unchecked Sendable {
    let witnessTables: [ProtocolLayout.DescriptorID: WitnessTable]

    private let storage: UnsafeMutableRawPointer
    private let representation: StubExistentialRepresentation
    private let valuePointer: UnsafeRawPointer
    private let objectPointer: UnsafeRawPointer?
    private let dynamicMetadata: UnsafeRawPointer

    init(
        _ target: P,
        layout: ProtocolLayout,
        representation: StubExistentialRepresentation
    ) throws {
        self.representation = representation
        storage = .allocate(
            byteCount: max(MemoryLayout<P>.size, 1),
            alignment: max(MemoryLayout<P>.alignment, 1)
        )
        storage.assumingMemoryBound(to: P.self).initialize(to: target)

        let witnessTableOffset: Int
        switch representation {
            case .opaque:
                let container = storage.assumingMemoryBound(
                    to: AnyExistentialContainer.self
                )
                valuePointer = container.pointee.projectValue()
                objectPointer = nil
                dynamicMetadata = (storage + 3 * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer.self)
                witnessTableOffset = 4

            case .classConstrained, .superclassConstrained:
                let object = storage.load(as: UnsafeRawPointer.self)
                objectPointer = object
                valuePointer = UnsafeRawPointer(storage)
                let instance = Unmanaged<AnyObject>.fromOpaque(object)
                    .takeUnretainedValue()
                dynamicMetadata = unsafeBitCast(
                    Swift.type(of: instance),
                    to: UnsafeRawPointer.self
                )
                witnessTableOffset = 1
        }

        let expectedWordCount = witnessTableOffset + layout.roots.count
        guard MemoryLayout<P>.size >= expectedWordCount * MemoryLayout<UInt>.size else {
            storage.assumingMemoryBound(to: P.self).deinitialize(count: 1)
            storage.deallocate()
            throw StubError.unsupportedProtocolShape(
                protocolName: String(reflecting: P.self),
                reason: "The forwarding target's existential storage does not contain the expected root witness tables."
            )
        }

        do {
            var tables: [ProtocolLayout.DescriptorID: WitnessTable] = [:]
            for (rootIndex, root) in layout.roots.enumerated() {
                let pointer =
                    (storage
                    + (witnessTableOffset + rootIndex) * MemoryLayout<UInt>.size)
                    .load(as: UnsafeRawPointer.self)
                try Stub<P>.collectLinkedWitnessTables(
                    descriptor: root,
                    witnessTable: WitnessTable(ptr: pointer),
                    layout: layout,
                    into: &tables
                )
            }
            witnessTables = tables
        } catch {
            storage.assumingMemoryBound(to: P.self).deinitialize(count: 1)
            storage.deallocate()
            throw error
        }
    }

    deinit {
        storage.assumingMemoryBound(to: P.self).deinitialize(count: 1)
        storage.deallocate()
    }

    var selfValue: UnsafeRawPointer {
        switch representation {
            case .opaque:
                return valuePointer
            case .classConstrained, .superclassConstrained:
                guard let objectPointer else {
                    preconditionFailure(
                        "[TestDoubles] A class-constrained Spy target has no object pointer."
                    )
                }
                return objectPointer
        }
    }

    var metadata: UnsafeRawPointer { dynamicMetadata }
}

final class ProtocolForwarder<P>: ProtocolForwarding, @unchecked Sendable {
    private struct CallPlan: @unchecked Sendable {
        let function: UnsafeRawPointer
        let selfValue: UnsafeRawPointer
        let witnessTable: UnsafeRawPointer
        let hiddenArgumentIndex: Int
        let isAsync: Bool
    }

    private struct ReadPlan: @unchecked Sendable {
        let entry: UnsafeRawPointer
        let descriptorSlot: UnsafeRawPointer
        let declarationDiscriminator: UInt16
        let resumeDiscriminator: UInt16
        let selfValue: UnsafeRawPointer
        let witnessTable: UnsafeRawPointer
        let hiddenArgumentIndex: Int
        let callerFrameSize: Int
        let resultIsIndirect: Bool
    }

    private final class ReadState:
        ReadCoroutineForwardingState,
        @unchecked Sendable
    {
        let yieldedStorage: UnsafeMutableRawPointer?

        private let owner: AnyObject
        private let resume: UnsafeRawPointer
        private let resumeDiscriminator: UInt16
        private let callerFrame: UnsafeMutableRawPointer
        private let storedFrame: UnsafeMutablePointer<TDCallFrame>
        private var didFinish = false

        init(
            owner: AnyObject,
            plan: ReadPlan,
            metadata: UnsafeRawPointer,
            frame: TrampolineCallFrame
        ) {
            self.owner = owner
            resumeDiscriminator = plan.resumeDiscriminator
            callerFrame = .allocate(
                byteCount: plan.callerFrameSize,
                alignment: 16
            )
            callerFrame.initializeMemory(
                as: UInt8.self,
                repeating: 0,
                count: plan.callerFrameSize
            )
            storedFrame = .allocate(capacity: 1)
            storedFrame.initialize(to: frame.snapshot)
            let targetFrame = TrampolineCallFrame(storedFrame)
            targetFrame.storeGeneralPurposeArgument(
                UInt(bitPattern: metadata),
                at: plan.hiddenArgumentIndex
            )
            targetFrame.storeGeneralPurposeArgument(
                UInt(bitPattern: plan.witnessTable),
                at: plan.hiddenArgumentIndex + 1
            )

            let result = td_swift_invoke_read_witness(
                plan.entry,
                plan.descriptorSlot,
                plan.declarationDiscriminator,
                plan.selfValue,
                storedFrame,
                callerFrame
            )
            guard let rawResume = result.state else {
                preconditionFailure(
                    "[TestDoubles] A forwarded read witness returned a null continuation."
                )
            }
            resume = UnsafeRawPointer(rawResume)
            yieldedStorage =
                plan.resultIsIndirect ? result.yieldedStorage : nil
            frame.restore(storedFrame.pointee)
        }

        deinit {
            precondition(
                didFinish,
                "[TestDoubles] A forwarded read coroutine was released before resumption."
            )
            storedFrame.deinitialize(count: 1)
            storedFrame.deallocate()
            callerFrame.deallocate()
        }

        func finish() {
            precondition(
                didFinish == false,
                "[TestDoubles] A forwarded read coroutine resumed more than once."
            )
            didFinish = true
            td_swift_resume_read_witness(
                resume,
                callerFrame,
                resumeDiscriminator
            )
            withExtendedLifetime(owner) {}
        }
    }

    private final class AsyncState:
        AsyncTrampolineDispatchState,
        @unchecked Sendable
    {
        private let owner: AnyObject
        private let function: UnsafeRawPointer
        private let selfValue: UnsafeRawPointer
        private let isThrowing: Bool
        private let storedFrame: UnsafeMutablePointer<TDCallFrame>

        init(
            owner: AnyObject,
            function: UnsafeRawPointer,
            selfValue: UnsafeRawPointer,
            isThrowing: Bool,
            frame: TDCallFrame
        ) {
            self.owner = owner
            self.function = function
            self.selfValue = selfValue
            self.isThrowing = isThrowing
            storedFrame = .allocate(capacity: 1)
            storedFrame.initialize(to: frame)
        }

        deinit {
            storedFrame.deinitialize(count: 1)
            storedFrame.deallocate()
        }

        func run() async {
            await tdSwiftInvokeAsyncWitness(
                function,
                selfValue,
                storedFrame,
                isThrowing
            )
            withExtendedLifetime(owner) {}
        }

        func finish(into frame: TrampolineCallFrame) {
            frame.restore(storedFrame.pointee)
        }
    }

    private let target: ForwardingTarget<P>
    private let plans: [Int: CallPlan]
    private let readPlans: [Int: ReadPlan]

    init(
        target: ForwardingTarget<P>,
        methods: [MethodDescriptor],
        layout: ProtocolLayout
    ) throws {
        self.target = target

        guard layout.nodes.allSatisfy({ $0.modifyCoroutineRequirements.isEmpty }) else {
            let protocolName =
                layout.nodes.first(where: { !$0.modifyCoroutineRequirements.isEmpty })?
                .descriptor.name ?? String(reflecting: P.self)
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Forwarding Spy does not yet support _modify coroutine requirements. Use a hand-written spy for mutable properties and subscripts."
            )
        }

        var readRequirements: [Int: ProtocolLayout.ReadCoroutineRequirement] = [:]
        for node in layout.nodes {
            for requirement in node.readCoroutineRequirements {
                readRequirements[requirement.recorderDispatchIndex] = requirement
            }
        }

        var plans: [Int: CallPlan] = [:]
        var readPlans: [Int: ReadPlan] = [:]
        for method in methods {
            let requirement = layout.callableRequirements[method.index]
            let protocolName = requirement.protocolDescriptor.name
            guard method.receiver == .instance, method.kind != .initializer else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Forwarding Spy supports instance requirements only; requirement \(method.index) uses a metatype receiver."
                )
            }
            guard method.returnConvention != .selfType,
                method.returnConvention != .optionalSelf
            else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Forwarding Spy does not yet support dynamic Self results in requirement \(method.index)."
                )
            }
            let concreteTypes = method.argumentTypes + [method.returnType]
            guard method.typedWitnessAdapterFactory == nil,
                concreteTypes.allSatisfy({ reflect($0).kind != .function })
            else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Forwarding Spy does not yet support function-valued arguments or results in requirement \(method.index)."
                )
            }

            let identifier = ProtocolLayout.DescriptorID(
                requirement.protocolDescriptor
            )
            guard let witnessTable = target.witnessTables[identifier] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "The forwarding target is missing a witness table for requirement \(method.index)."
                )
            }
            let witnessSlot =
                witnessTable.ptr
                + (1 + method.witnessIndex) * MemoryLayout<UInt>.size
            let signedFunction = witnessSlot.load(as: UnsafeRawPointer.self)

            if let readRequirement = readRequirements[method.index] {
                guard method.kind == .getter,
                    method.receiver == readRequirement.receiver,
                    method.isAsync == false,
                    method.isThrowing == false,
                    method.arguments.allSatisfy({ $0.ownership == .borrowed }),
                    let resumeDiscriminator =
                        ReadCoroutineRuntime.resumeDiscriminator(for: method)
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason:
                            "The read requirement at witness index \(readRequirement.witnessIndex) is outside the supported synchronous, nonthrowing borrowed-value forwarding ABI."
                    )
                }
                let flags = requirement.protocolDescriptor.requirements[
                    method.witnessIndex
                ].flags
                let declarationDiscriminator = UInt16(
                    truncatingIfNeeded: flags.bits >> 16
                )
                var descriptorTarget = TDReadWitnessTarget()
                guard
                    td_prepare_read_witness_target(
                        signedFunction,
                        UnsafeRawPointer(witnessSlot),
                        declarationDiscriminator,
                        &descriptorTarget
                    ),
                    let entry = descriptorTarget.entry,
                    descriptorTarget.callerFrameSize == 32
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason:
                            "The forwarding target's read witness at index \(readRequirement.witnessIndex) is not a supported Swift 6.3 yield_once_2 descriptor with a 32-byte caller frame."
                    )
                }
                #if arch(x86_64)
                    let initialGeneralPurposeOffset = 2
                #else
                    let initialGeneralPurposeOffset = 1
                #endif
                let hiddenArgumentIndex = try Self.hiddenArgumentIndex(
                    for: method,
                    protocolName: protocolName,
                    initialGeneralPurposeOffset: initialGeneralPurposeOffset
                )
                readPlans[method.index] = ReadPlan(
                    entry: entry,
                    descriptorSlot: UnsafeRawPointer(witnessSlot),
                    declarationDiscriminator: declarationDiscriminator,
                    resumeDiscriminator: resumeDiscriminator,
                    selfValue: target.selfValue,
                    witnessTable: witnessTable.ptr,
                    hiddenArgumentIndex: hiddenArgumentIndex,
                    callerFrameSize: Int(descriptorTarget.callerFrameSize),
                    resultIsIndirect: {
                        if case .indirect = method.result.layout { return true }
                        return false
                    }()
                )
                continue
            }

            let hiddenArgumentIndex = try Self.hiddenArgumentIndex(
                for: method,
                protocolName: protocolName
            )
            let function =
                if method.isAsync {
                    td_strip_async_witness_pointer(signedFunction)
                } else {
                    td_strip_witness_function_pointer(signedFunction)
                }
            guard let function else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "The forwarding target has a null witness for requirement \(method.index)."
                )
            }
            plans[method.index] = CallPlan(
                function: function,
                selfValue: target.selfValue,
                witnessTable: witnessTable.ptr,
                hiddenArgumentIndex: hiddenArgumentIndex,
                isAsync: method.isAsync
            )
        }
        self.plans = plans
        self.readPlans = readPlans
    }

    func forward(_ method: MethodDescriptor, frame: TrampolineCallFrame) {
        let plan = prepare(method, frame: frame)
        precondition(
            plan.isAsync == false,
            "[TestDoubles] An async Spy requirement entered synchronous forwarding."
        )
        td_swift_invoke_witness(plan.function, plan.selfValue, frame.pointer)
    }

    func makeReadState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any ReadCoroutineForwardingState {
        guard let plan = readPlans[method.index] else {
            preconditionFailure(
                "[TestDoubles] No read forwarding plan exists for Spy requirement \(method.index)."
            )
        }
        return ReadState(
            owner: self,
            plan: plan,
            metadata: target.metadata,
            frame: frame
        )
    }

    func makeAsyncState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any AsyncTrampolineDispatchState {
        let plan = prepare(method, frame: frame)
        precondition(
            plan.isAsync,
            "[TestDoubles] A synchronous Spy requirement entered async forwarding."
        )
        return AsyncState(
            owner: self,
            function: plan.function,
            selfValue: plan.selfValue,
            isThrowing: method.isThrowing,
            frame: frame.snapshot
        )
    }

    private func prepare(
        _ method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> CallPlan {
        guard let plan = plans[method.index] else {
            preconditionFailure(
                "[TestDoubles] No forwarding plan exists for Spy requirement \(method.index)."
            )
        }
        frame.storeGeneralPurposeArgument(
            UInt(bitPattern: target.metadata),
            at: plan.hiddenArgumentIndex
        )
        frame.storeGeneralPurposeArgument(
            UInt(bitPattern: plan.witnessTable),
            at: plan.hiddenArgumentIndex + 1
        )
        return plan
    }

    private static func hiddenArgumentIndex(
        for method: MethodDescriptor,
        protocolName: String,
        initialGeneralPurposeOffset: Int = 0
    ) throws -> Int {
        var generalPurpose = initialGeneralPurposeOffset
        var floatingPoint = 0
        var stack = 0

        if method.isAsync, case .indirect = method.result.layout {
            generalPurpose += 1
        }

        func consumeGeneralPurpose(_ count: Int) {
            for _ in 0 ..< count {
                if generalPurpose < TrampolineCallFrame.generalPurposeArgumentLimit {
                    generalPurpose += 1
                } else {
                    stack += 1
                }
            }
        }

        func consumeFloatingPoint() {
            if floatingPoint < TrampolineCallFrame.floatingPointArgumentLimit {
                floatingPoint += 1
            } else {
                stack += 1
            }
        }

        for argument in method.arguments {
            switch argument.value.layout {
                case .void:
                    break
                case .integer(let words):
                    consumeGeneralPurpose(words)
                case .floatingPoint:
                    consumeFloatingPoint()
                case .aggregate(let parts):
                    for part in parts {
                        switch part.register {
                            case .gp: consumeGeneralPurpose(1)
                            case .fp: consumeFloatingPoint()
                        }
                    }
                case .indirect:
                    consumeGeneralPurpose(1)
            }
        }
        if method.typedErrorUsesIndirectResultSlot {
            consumeGeneralPurpose(1)
        }

        guard stack == 0,
            generalPurpose + 2 <= TrampolineCallFrame.generalPurposeArgumentLimit
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Forwarding Spy requirement \(method.index) uses stack arguments or leaves no registers for its target metadata and witness table. Use fewer arguments or a hand-written spy."
            )
        }
        return generalPurpose
    }
}
