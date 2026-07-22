import CTestDoublesTrampoline

final class ForwardedModifyState:
    ModifyCoroutineForwardingState,
    @unchecked Sendable
{
    let yieldedStorage: UnsafeMutableRawPointer

    private let owner: AnyObject
    private let resume: UnsafeRawPointer
    private let callerFrame: UnsafeMutableRawPointer
    private let storedFrame: UnsafeMutablePointer<TDCallFrame>
    private var didFinish = false

    init(
        owner: AnyObject,
        plan: ForwardedModifyPlan,
        metadata: UnsafeRawPointer,
        frame: TrampolineCallFrame
    ) {
        self.owner = owner
        callerFrame = .allocate(byteCount: 32, alignment: 16)
        callerFrame.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: 32
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

        let result = td_swift_invoke_modify_witness(
            plan.entry,
            plan.entrySlot,
            plan.declarationDiscriminator,
            plan.selfValue,
            storedFrame,
            callerFrame
        )
        guard let rawResume = result.state else {
            preconditionFailure(
                "[TestDoubles] A forwarded _modify witness returned a null continuation."
            )
        }
        guard let rawYieldedStorage = result.yieldedStorage else {
            preconditionFailure(
                "[TestDoubles] A forwarded _modify witness returned null yielded storage."
            )
        }
        resume = UnsafeRawPointer(rawResume)
        yieldedStorage = rawYieldedStorage
    }

    deinit {
        precondition(
            didFinish,
            "[TestDoubles] A forwarded _modify coroutine was released before resumption."
        )
        storedFrame.deinitialize(count: 1)
        storedFrame.deallocate()
        callerFrame.deallocate()
    }

    func finish(isAborting: Bool) {
        precondition(
            didFinish == false,
            "[TestDoubles] A forwarded _modify coroutine resumed more than once."
        )
        didFinish = true
        td_swift_resume_modify_witness(
            resume,
            callerFrame,
            isAborting
        )
        withExtendedLifetime(owner) {}
    }
}

final class ForwardedReadState:
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
        plan: ForwardedReadPlan,
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

final class ForwardedAsyncState:
    AsyncTrampolineDispatchState,
    @unchecked Sendable
{
    private let owner: AnyObject
    private let function: UnsafeRawPointer
    private let selfValue: UnsafeRawPointer
    private let isThrowing: Bool
    private let storedFrame: UnsafeMutablePointer<TDCallFrame>
    private let stackArguments:
        UnsafeMutablePointer<
            TDAsyncWitnessStackArguments
        >?

    init(
        owner: AnyObject,
        plan: ForwardedCallPlan,
        metadata: UnsafeRawPointer,
        isThrowing: Bool,
        frame: TrampolineCallFrame
    ) {
        self.owner = owner
        function = plan.function
        selfValue = plan.selfValue
        self.isThrowing = isThrowing
        storedFrame = .allocate(capacity: 1)
        storedFrame.initialize(to: frame.snapshot)
        if let stackPlan = plan.asyncStackPlan {
            let storage = UnsafeMutablePointer<
                TDAsyncWitnessStackArguments
            >.allocate(capacity: 1)
            storage.initialize(
                to: TDAsyncWitnessStackArguments(
                    visible: frame.scalarBits(
                        at: stackPlan.visibleArgumentLocation
                    ),
                    metadata: UInt64(UInt(bitPattern: metadata)),
                    witnessTable: UInt64(
                        UInt(bitPattern: plan.witnessTable)
                    )
                )
            )
            stackArguments = storage
        } else {
            stackArguments = nil
        }
    }

    deinit {
        stackArguments?.deinitialize(count: 1)
        stackArguments?.deallocate()
        storedFrame.deinitialize(count: 1)
        storedFrame.deallocate()
    }

    func run() async {
        await tdSwiftInvokeAsyncWitness(
            function,
            selfValue,
            storedFrame,
            isThrowing,
            stackArguments
        )
        withExtendedLifetime(owner) {}
    }

    func finish(into frame: TrampolineCallFrame) {
        frame.restore(storedFrame.pointee)
    }
}
