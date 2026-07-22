import TestDoublesFixtures
import Testing
@testable import TestDoubles
#if canImport(Foundation)
    import Foundation
#endif

#if canImport(ObjectiveC)
    private final class SuperclassSelfArgumentProbe:
        NSObject, ExternalArgumentOnlySelfProbe
    {
        func accept(_ value: SuperclassSelfArgumentProbe) {}

        func acceptOptional(_ value: SuperclassSelfArgumentProbe?) {}

        func marker() -> Int { 0 }
    }
#endif

private actor SelfArgumentSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private protocol SelfArgumentAsyncInvocation: Sendable {
    func run() async
}

private final class ConsumingClassAsyncInvocation<
    P: ExternalClassSelfArgumentProbe
>: SelfArgumentAsyncInvocation, @unchecked Sendable {
    private let receiver: P
    private var source: P?

    init(receiver: P, source: consuming P) {
        self.receiver = receiver
        self.source = source
    }

    func run() async {
        guard let source else { return }
        self.source = nil
        await receiver.consumeAsynchronously(consume source)
    }
}

@Suite struct SelfArgumentTests {
    @Test func ordinaryOpaqueDescriptorsUseIndirectSelfStorage() throws {
        _ = RealExternalSelfArgumentProbe()
        let stub = try Stub<any ExternalSelfArgumentProbe>()

        try assertSelfArgumentDescriptors(
            stub,
            expectedLayout: .indirect
        )
    }

    @Test func classConstrainedDescriptorsUseOneReferenceWord() throws {
        _ = RealExternalClassSelfArgumentProbe()
        let stub = try Stub<any ExternalClassSelfArgumentProbe>()

        try assertSelfArgumentDescriptors(
            stub,
            expectedLayout: .reference
        )
    }

    @Test func inheritedOpaqueSelfRequirementsRemainIndirect() throws {
        _ = RealExternalInheritedClassSelfArgumentProbe()
        let stub = try Stub<any ExternalInheritedClassSelfArgumentProbe>()
        let method = try #require(stub.recorder.runtimeMethod(for: 0))
        let roundTrip = try #require(stub.recorder.runtimeMethod(for: 7))
        #expect(method.argumentLayouts.first.map(isIndirect) == true)
        #expect(roundTrip.argumentLayouts.first.map(isIndirect) == true)
        #expect(isIndirect(roundTrip.returnLayout))

        stub.when { captureAccept($0) }.thenDoNothing()
        let source = stub()
        invokeAccept(source)
        stub.verify { captureAccept($0) }
    }

    @Test func ordinaryOpaqueArgumentsWorkEndToEnd() async throws {
        _ = RealExternalSelfArgumentProbe()
        let stub = try Stub<any ExternalSelfArgumentProbe>()
        await configureOpaqueSelfArgumentStub(stub)

        let source = stub()
        try await exerciseSelfArgumentProbe(source)

        #expect(invokeMarker(source) == 42)
        verifyOpaqueSelfArgumentCalls(stub)
        await verifyOpaqueAsyncSelfArgumentCalls(stub)
    }

    @Test func classConstrainedArgumentsWorkEndToEnd() async throws {
        _ = RealExternalClassSelfArgumentProbe()
        let stub = try Stub<any ExternalClassSelfArgumentProbe>()
        await configureClassSelfArgumentStub(stub)

        let source = stub()
        try await exerciseClassSelfArgumentProbe(source)

        #expect(invokeClassMarker(source) == 42)
        verifyClassSelfArgumentCalls(stub)
        await verifyClassAsyncSelfArgumentCalls(stub)
    }

    @Test func consumingClassArgumentsReleaseWithTheirRuntimeGraph() async throws {
        let weakReference = try await exerciseConsumingClassLifetime()

        #expect(weakReference.value == nil)
    }

    @Test func consumingAsyncClassArgumentSurvivesBoxedIngressSuspension() async throws {
        _ = RealExternalClassSelfArgumentProbe()
        let stub = try Stub<any ExternalClassSelfArgumentProbe>()
        let target = stub()
        let gate = SelfArgumentSuspensionGate()
        await configureSuspendingClassConsume(
            stub,
            placeholder: target,
            gate: gate
        )

        let started = try startConsumingClassAsyncCall(receiver: target)
        var task: Task<Void, Never>? = started.task
        await gate.waitUntilStarted()
        #expect(started.weakSource.value != nil)

        await gate.release()
        await task?.value
        task = nil
        #expect(started.weakSource.value == nil)
    }

    @Test func capturedAndAccessedClassArgumentsOwnValidRuntimeGraphs() throws {
        _ = RealExternalClassSelfArgumentProbe()
        var targetStub: Stub<any ExternalClassSelfArgumentProbe>? = try Stub()
        var sourceStub: Stub<any ExternalClassSelfArgumentProbe>? = try Stub()
        do {
            let stub = try #require(targetStub)
            stub.when { captureClassAccept($0) }.thenDoNothing()
            stub.when { $0.marker() }.thenReturn(83)
        }

        var target: (any ExternalClassSelfArgumentProbe)?
        var source: (any ExternalClassSelfArgumentProbe)?
        do {
            let targetStub = try #require(targetStub)
            let sourceStub = try #require(sourceStub)
            target = targetStub()
            source = sourceStub()
        }
        let weakSource: WeakReference<AnyObject>
        do {
            let target = try #require(target)
            let source = try #require(source)
            weakSource = WeakReference(source as AnyObject)
            try invokeClassAccept(target, source: source)
        }

        source = nil
        sourceStub = nil
        #expect(weakSource.value == nil)

        let captured: any ExternalClassSelfArgumentProbe
        let accessed: any ExternalClassSelfArgumentProbe
        do {
            let stub = try #require(targetStub)
            let target = try #require(target)
            captured = try captureRecordedClassAccept(stub, placeholder: target)
            accessed = try accessRecordedClassAccept(stub, placeholder: target)
        }

        target = nil
        targetStub = nil
        #expect(invokeClassMarker(captured) == 83)
        #expect(invokeClassMarker(accessed) == 83)
    }

    @Test func recordedClassArgumentPreservesIdentityWhileOriginalLives() throws {
        _ = RealExternalClassSelfArgumentProbe()
        let stub = try Stub<any ExternalClassSelfArgumentProbe>()
        stub.when { captureClassAccept($0) }.thenDoNothing()

        let source = stub()
        invokeClassAccept(source)
        verifyRecordedClassAcceptIsIdentical(stub, to: source)
    }

    @Test func recordedNilOptionalSelfRemainsNil() throws {
        _ = RealExternalClassSelfArgumentProbe()
        let stub = try Stub<any ExternalClassSelfArgumentProbe>()
        stub.when { captureClassOptional($0) }.thenDoNothing()

        let source = stub()
        invokeClassOptional(source, includesValue: false)
        try assertRecordedNilClassOptional(stub, placeholder: source)
    }

    @Test func inoutSelfFailsClosedDuringAutomaticDiscovery() {
        _ = RealExternalInoutSelfArgumentProbe()

        expectUnsupportedProtocolShape(containing: "inout Self argument") {
            _ = try Stub<any ExternalInoutSelfArgumentProbe>()
        }
    }

    @Test func nestedOptionalSelfFailsClosedDuringAutomaticDiscovery() {
        _ = RealExternalNestedOptionalSelfArgumentProbe()

        expectUnsupportedProtocolShape(containing: "embeds Self") {
            _ = try Stub<any ExternalNestedOptionalSelfArgumentProbe>()
        }
    }

    @Test func widerSelfFailsClosedDuringAutomaticDiscovery() {
        _ = RealExternalArraySelfArgumentProbe()

        expectUnsupportedProtocolShape(containing: "embeds Self") {
            _ = try Stub<any ExternalArraySelfArgumentProbe>()
        }
    }

    @Test func throwingSelfArgumentFailsClosedAtConstruction() {
        _ = RealExternalThrowingSelfArgumentProbe()

        expectUnsupportedProtocolShape(containing: "throwing effects") {
            _ = try Stub<any ExternalThrowingSelfArgumentProbe>()
        }
    }

    #if canImport(ObjectiveC)
        @Test func superclassConstrainedSelfArgumentFailsClosed() {
            _ = SuperclassSelfArgumentProbe()

            expectUnsupportedProtocolShape(
                containing: "Self argument in a superclass-constrained existential"
            ) {
                _ = try Stub<any NSObject & ExternalArgumentOnlySelfProbe>()
            }
        }
    #endif

    @Test func forwardingSpyRejectsSelfArgumentsAtConstruction() {
        _ = RealExternalArgumentOnlySelfProbe()

        expectUnsupportedProtocolShape(
            containing: "Forwarding Spy does not support direct or Optional Self arguments"
        ) {
            _ = try Spy<any ExternalArgumentOnlySelfProbe>(
                forwardingTo: RealExternalArgumentOnlySelfProbe()
            )
        }
    }
}

private func configureOpaqueSelfArgumentStub(
    _ stub: Stub<any ExternalSelfArgumentProbe>
) async {
    stub.when { captureAccept($0) }.thenDoNothing()
    stub.when { captureBorrow($0) }.thenDoNothing()
    stub.when { captureConsume($0) }.thenDoNothing()
    stub.when { captureOptional($0) }.thenDoNothing()
    stub.when { captureConsumingOptional($0) }.thenDoNothing()
    await stub.when { await captureAsync($0) }.thenDoNothing()
    await stub.when { await captureConsumingAsync($0) }.thenDoNothing()
    stub.when(returningSelf: { captureRoundTrip($0) }).thenReturnValue()
    stub.when(
        returningOptionalSelf: { captureOptionalRoundTrip($0) }
    ).thenReturnValue()
    stub.when { $0.marker() }.thenReturn(42)
}

private func configureClassSelfArgumentStub(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>
) async {
    stub.when { captureClassAccept($0) }.thenDoNothing()
    stub.when { captureClassBorrow($0) }.thenDoNothing()
    stub.when { captureClassConsume($0) }.thenDoNothing()
    stub.when { captureClassOptional($0) }.thenDoNothing()
    stub.when { captureClassConsumingOptional($0) }.thenDoNothing()
    await stub.when { await captureClassAsync($0) }.thenDoNothing()
    await stub.when { await captureClassConsumingAsync($0) }.thenDoNothing()
    stub.when(returningSelf: { captureClassRoundTrip($0) }).thenReturnValue()
    stub.when(
        returningOptionalSelf: { captureClassOptionalRoundTrip($0) }
    ).thenReturnValue()
    stub.when { $0.marker() }.thenReturn(42)
}

private func exerciseSelfArgumentProbe<P: ExternalSelfArgumentProbe>(
    _ value: P
) async throws {
    invokeAccept(value)
    invokeBorrow(value)
    invokeConsume(value)
    invokeOptional(value, includesValue: true)
    invokeOptional(value, includesValue: false)
    invokeConsumingOptional(value, includesValue: true)
    invokeConsumingOptional(value, includesValue: false)
    await invokeAsync(value)
    await invokeConsumingAsync(value)

    let returned = invokeRoundTrip(value)
    let optionalReturned = try #require(
        invokeOptionalRoundTrip(value, includesValue: true)
    )
    let optionalReturnedFromNil = try #require(
        invokeOptionalRoundTrip(value, includesValue: false)
    )
    #expect(invokeMarker(returned) == 42)
    #expect(invokeMarker(optionalReturned) == 42)
    #expect(invokeMarker(optionalReturnedFromNil) == 42)
}

private func exerciseClassSelfArgumentProbe<P: ExternalClassSelfArgumentProbe>(
    _ value: P
) async throws {
    invokeClassAccept(value)
    invokeClassBorrow(value)
    invokeClassConsume(value)
    invokeClassOptional(value, includesValue: true)
    invokeClassOptional(value, includesValue: false)
    invokeClassConsumingOptional(value, includesValue: true)
    invokeClassConsumingOptional(value, includesValue: false)
    await invokeClassAsync(value)
    await invokeClassConsumingAsync(value)

    let returned = invokeClassRoundTrip(value)
    let optionalReturned = try #require(
        invokeClassOptionalRoundTrip(value, includesValue: true)
    )
    let optionalReturnedFromNil = try #require(
        invokeClassOptionalRoundTrip(value, includesValue: false)
    )
    #expect(invokeClassMarker(returned) == 42)
    #expect(invokeClassMarker(optionalReturned) == 42)
    #expect(invokeClassMarker(optionalReturnedFromNil) == 42)
}

private func verifyOpaqueSelfArgumentCalls(
    _ stub: Stub<any ExternalSelfArgumentProbe>
) {
    stub.verify { captureAccept($0) }
    stub.verify { captureBorrow($0) }
    stub.verify { captureConsume($0) }
    stub.verify(.exactly(2)) { captureOptional($0) }
    stub.verify(.exactly(2)) { captureConsumingOptional($0) }
    stub.verify { captureRoundTrip($0) }
    stub.verify(.exactly(2)) { captureOptionalRoundTrip($0) }
}

private func verifyOpaqueAsyncSelfArgumentCalls(
    _ stub: Stub<any ExternalSelfArgumentProbe>
) async {
    await stub.verify { await captureAsync($0) }
    await stub.verify { await captureConsumingAsync($0) }
}

private func verifyClassSelfArgumentCalls(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>
) {
    stub.verify { captureClassAccept($0) }
    stub.verify { captureClassBorrow($0) }
    stub.verify { captureClassConsume($0) }
    stub.verify(.exactly(2)) { captureClassOptional($0) }
    stub.verify(.exactly(2)) { captureClassConsumingOptional($0) }
    stub.verify { captureClassRoundTrip($0) }
    stub.verify(.exactly(2)) { captureClassOptionalRoundTrip($0) }
}

private func verifyClassAsyncSelfArgumentCalls(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>
) async {
    await stub.verify { await captureClassAsync($0) }
    await stub.verify { await captureClassConsumingAsync($0) }
}

private func exerciseConsumingClassLifetime() async throws -> WeakReference<AnyObject> {
    _ = RealExternalClassSelfArgumentProbe()
    let stub = try Stub<any ExternalClassSelfArgumentProbe>()
    stub.when { captureClassConsume($0) }.thenDoNothing()
    await stub.when { await captureClassConsumingAsync($0) }.thenDoNothing()
    stub.when { $0.marker() }.thenReturn(71)

    let source = stub()
    let weakReference = WeakReference(source as AnyObject)
    invokeClassConsume(source)
    await invokeClassConsumingAsync(source)
    #expect(invokeClassMarker(source) == 71)
    return weakReference
}

private func configureSuspendingClassConsume<
    P: ExternalClassSelfArgumentProbe
>(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>,
    placeholder: P,
    gate: SelfArgumentSuspensionGate
) async {
    await stub.when { await captureClassConsumingAsync($0) }.then {
        (argument: P) async in
        await gate.suspend()
        withExtendedLifetime(argument) {}
    }
}

private func startConsumingClassAsyncCall<
    P: ExternalClassSelfArgumentProbe
>(
    receiver: P
) throws -> (task: Task<Void, Never>, weakSource: WeakReference<AnyObject>) {
    let sourceStub = try Stub<any ExternalClassSelfArgumentProbe>()
    let source = try #require(sourceStub() as? P)
    let weakSource = WeakReference(source as AnyObject)
    let invocation: any SelfArgumentAsyncInvocation = ConsumingClassAsyncInvocation(
        receiver: receiver,
        source: source
    )
    let task = Task {
        await invocation.run()
    }
    return (task, weakSource)
}

private func invokeClassAccept<P: ExternalClassSelfArgumentProbe>(
    _ receiver: P,
    source: any ExternalClassSelfArgumentProbe
) throws {
    let source = try #require(source as? P)
    receiver.accept(source)
}

private func captureRecordedClassAccept<P: ExternalClassSelfArgumentProbe>(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>,
    placeholder: P
) throws -> any ExternalClassSelfArgumentProbe {
    let captor = ArgumentCaptor<P>()
    stub.verify {
        _ = captor.capture(using: placeholder)
        recordClassAccept($0)
    }
    return try #require(captor.first)
}

private func accessRecordedClassAccept<P: ExternalClassSelfArgumentProbe>(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>,
    placeholder: P
) throws -> any ExternalClassSelfArgumentProbe {
    let values: [P] = stub.invocations {
        _ = any(using: placeholder)
        recordClassAccept($0)
    }
    return try #require(values.first)
}

private func verifyRecordedClassAcceptIsIdentical<
    P: ExternalClassSelfArgumentProbe
>(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>,
    to expected: P
) {
    stub.verify {
        _ = identical(to: expected)
        recordClassAccept($0)
    }
}

private func assertRecordedNilClassOptional<P: ExternalClassSelfArgumentProbe>(
    _ stub: Stub<any ExternalClassSelfArgumentProbe>,
    placeholder: P,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let captor = ArgumentCaptor<P?>()
    stub.verify {
        _ = captor.capture(using: Optional(placeholder))
        recordClassOptional($0)
    }
    #expect(captor.values.count == 1, sourceLocation: sourceLocation)
    #expect(captor.values[0] == nil, sourceLocation: sourceLocation)

    let values: [P?] = stub.invocations {
        captureClassOptional($0)
    }
    #expect(values.count == 1, sourceLocation: sourceLocation)
    #expect(values[0] == nil, sourceLocation: sourceLocation)
}

private func recordClassAccept<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.accept(value)
}

private func recordClassOptional<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.acceptOptional(value)
}

private func assertSelfArgumentDescriptors<P>(
    _ stub: Stub<P>,
    expectedLayout: ExpectedSelfArgumentLayout,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let expected: [(WitnessValueConvention, WitnessArgumentOwnership, Bool)] = [
        (.selfType, .borrowed, false),
        (.selfType, .borrowed, false),
        (.selfType, .owned, false),
        (.optionalSelf, .borrowed, false),
        (.optionalSelf, .owned, false),
        (.selfType, .borrowed, true),
        (.selfType, .owned, true)
    ]
    for (index, expectation) in expected.enumerated() {
        let method = try #require(
            stub.recorder.runtimeMethod(for: index),
            sourceLocation: sourceLocation
        )
        #expect(
            method.argumentConventions == [expectation.0],
            sourceLocation: sourceLocation
        )
        #expect(
            method.argumentOwnerships == [expectation.1],
            sourceLocation: sourceLocation
        )
        #expect(
            method.argumentLayouts.first.map {
                matches($0, expectedLayout: expectedLayout)
            } == true,
            sourceLocation: sourceLocation
        )
        #expect(method.isAsync == expectation.2, sourceLocation: sourceLocation)
    }

    let roundTrip = try #require(
        stub.recorder.runtimeMethod(for: 7),
        sourceLocation: sourceLocation
    )
    #expect(
        roundTrip.argumentConventions == [.selfType],
        sourceLocation: sourceLocation
    )
    #expect(roundTrip.returnConvention == .selfType, sourceLocation: sourceLocation)
    #expect(
        roundTrip.argumentLayouts.first.map {
            matches($0, expectedLayout: expectedLayout)
        } == true,
        sourceLocation: sourceLocation
    )
    #expect(
        matches(roundTrip.returnLayout, expectedLayout: expectedLayout),
        sourceLocation: sourceLocation
    )

    let optionalRoundTrip = try #require(
        stub.recorder.runtimeMethod(for: 8),
        sourceLocation: sourceLocation
    )
    #expect(
        optionalRoundTrip.argumentConventions == [.optionalSelf],
        sourceLocation: sourceLocation
    )
    #expect(
        optionalRoundTrip.returnConvention == .optionalSelf,
        sourceLocation: sourceLocation
    )
    #expect(
        optionalRoundTrip.argumentLayouts.first.map {
            matches($0, expectedLayout: expectedLayout)
        } == true,
        sourceLocation: sourceLocation
    )
    #expect(
        matches(optionalRoundTrip.returnLayout, expectedLayout: expectedLayout),
        sourceLocation: sourceLocation
    )
}

private enum ExpectedSelfArgumentLayout {
    case indirect
    case reference
}

private func matches(
    _ layout: ABIClass,
    expectedLayout: ExpectedSelfArgumentLayout
) -> Bool {
    switch (layout, expectedLayout) {
        case (.indirect, .indirect), (.integer(words: 1), .reference): true
        default: false
    }
}

private func isIndirect(_ layout: ABIClass) -> Bool {
    if case .indirect = layout { true } else { false }
}

private func captureAccept<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.accept(any(using: value))
}

private func captureBorrow<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.borrow(any(using: value))
}

private func captureConsume<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.consume(any(using: value))
}

private func captureOptional<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.acceptOptional(any(using: Optional(value)))
}

private func captureConsumingOptional<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.consumeOptional(any(using: Optional(value)))
}

private func captureAsync<P: ExternalSelfArgumentProbe>(_ value: P) async {
    await value.acceptAsynchronously(any(using: value))
}

private func captureConsumingAsync<P: ExternalSelfArgumentProbe>(_ value: P) async {
    await value.consumeAsynchronously(any(using: value))
}

private func captureRoundTrip<P: ExternalSelfArgumentProbe>(_ value: P) -> P {
    value.roundTrip(any(using: value))
}

private func captureOptionalRoundTrip<P: ExternalSelfArgumentProbe>(
    _ value: P
) -> P? {
    value.optionalRoundTrip(any(using: Optional(value)))
}

private func captureClassAccept<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.accept(any(using: value))
}

private func captureClassBorrow<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.borrow(any(using: value))
}

private func captureClassConsume<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.consume(any(using: value))
}

private func captureClassOptional<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.acceptOptional(any(using: Optional(value)))
}

private func captureClassConsumingOptional<P: ExternalClassSelfArgumentProbe>(
    _ value: P
) {
    value.consumeOptional(any(using: Optional(value)))
}

private func captureClassAsync<P: ExternalClassSelfArgumentProbe>(_ value: P) async {
    await value.acceptAsynchronously(any(using: value))
}

private func captureClassConsumingAsync<P: ExternalClassSelfArgumentProbe>(
    _ value: P
) async {
    await value.consumeAsynchronously(any(using: value))
}

private func captureClassRoundTrip<P: ExternalClassSelfArgumentProbe>(
    _ value: P
) -> P {
    value.roundTrip(any(using: value))
}

private func captureClassOptionalRoundTrip<P: ExternalClassSelfArgumentProbe>(
    _ value: P
) -> P? {
    value.optionalRoundTrip(any(using: Optional(value)))
}

private func invokeAccept<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.accept(value)
}

private func invokeBorrow<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.borrow(value)
}

private func invokeConsume<P: ExternalSelfArgumentProbe>(_ value: P) {
    value.consume(value)
}

private func invokeOptional<P: ExternalSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) {
    value.acceptOptional(includesValue ? value : nil)
}

private func invokeConsumingOptional<P: ExternalSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) {
    value.consumeOptional(includesValue ? value : nil)
}

private func invokeAsync<P: ExternalSelfArgumentProbe>(_ value: P) async {
    await value.acceptAsynchronously(value)
}

private func invokeConsumingAsync<P: ExternalSelfArgumentProbe>(_ value: P) async {
    await value.consumeAsynchronously(value)
}

private func invokeRoundTrip<P: ExternalSelfArgumentProbe>(_ value: P) -> P {
    value.roundTrip(value)
}

private func invokeOptionalRoundTrip<P: ExternalSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) -> P? {
    value.optionalRoundTrip(includesValue ? value : nil)
}

private func invokeMarker<P: ExternalSelfArgumentProbe>(_ value: P) -> Int {
    value.marker()
}

private func invokeClassAccept<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.accept(value)
}

private func invokeClassBorrow<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.borrow(value)
}

private func invokeClassConsume<P: ExternalClassSelfArgumentProbe>(_ value: P) {
    value.consume(value)
}

private func invokeClassOptional<P: ExternalClassSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) {
    value.acceptOptional(includesValue ? value : nil)
}

private func invokeClassConsumingOptional<P: ExternalClassSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) {
    value.consumeOptional(includesValue ? value : nil)
}

private func invokeClassAsync<P: ExternalClassSelfArgumentProbe>(_ value: P) async {
    await value.acceptAsynchronously(value)
}

private func invokeClassConsumingAsync<P: ExternalClassSelfArgumentProbe>(
    _ value: P
) async {
    await value.consumeAsynchronously(value)
}

private func invokeClassRoundTrip<P: ExternalClassSelfArgumentProbe>(_ value: P) -> P {
    value.roundTrip(value)
}

private func invokeClassOptionalRoundTrip<P: ExternalClassSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) -> P? {
    value.optionalRoundTrip(includesValue ? value : nil)
}

private func invokeClassMarker<P: ExternalClassSelfArgumentProbe>(_ value: P) -> Int {
    value.marker()
}
