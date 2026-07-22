import TestDoublesFixtures
import Testing
@testable import TestDoubles

@Suite struct ReferenceAssociatedTypeTests {
    @Test func automaticDiscoveryUsesDirectReferenceTransport() throws {
        _ = RealExternalReferenceAssociatedProbe()
        let stub = try Stub<
            any ExternalReferenceAssociatedProbe<ExternalReferenceAssociatedBox>
        >()
        let methods = try (0 ..< 8).map {
            try #require(stub.recorder.runtimeMethod(for: $0))
        }

        assertDirectReference(methods[0].arguments[0].value)
        assertDirectReference(methods[1].arguments[0].value)
        assertDirectReference(methods[1].result)
        #expect(methods[1].arguments[0].ownership == .borrowed)
        assertDirectReference(methods[2].arguments[0].value)
        #expect(methods[2].arguments[0].ownership == .owned)
        assertOptionalReference(methods[3].arguments[0].value)
        assertOptionalReference(methods[3].result)
        assertDirectReference(methods[4].arguments[0].value)
        assertDirectReference(methods[4].result)
        #expect(methods[4].isAsync)
        assertDirectReference(methods[5].arguments[0].value)
        #expect(methods[5].arguments[0].ownership == .owned)
        #expect(methods[5].isAsync)
        assertDirectReference(methods[6].arguments[0].value)
        assertDirectReference(methods[6].result)
        #expect(methods[6].typedErrorUsesIndirectResultSlot == false)
        assertOptionalReference(methods[7].arguments[0].value)
        assertOptionalReference(methods[7].result)
        #expect(methods[7].isAsync)
        #expect(methods[7].typedErrorUsesIndirectResultSlot == false)
    }

    @Test func synchronousCallsPreserveIdentityAndMatching() throws {
        _ = RealExternalReferenceAssociatedProbe()
        typealias Probe = any ExternalReferenceAssociatedProbe<
            ExternalReferenceAssociatedBox
        >
        let stub = try Stub<Probe>()
        let input = ExternalReferenceAssociatedBox(id: 1)
        let output = ExternalReferenceAssociatedBox(id: 2)
        let optionalOutput = ExternalReferenceAssociatedBox(id: 3)

        stub.when { $0.accept(identical(to: input)) }.thenDoNothing()
        stub.when(returning: output) {
            $0.transform(identical(to: input))
        }.thenReturn(output)
        stub.when(returning: Optional(optionalOutput)) {
            $0.optional(any(using: Optional(input)))
        }.thenReturn(Optional(optionalOutput))

        let probe: Probe = stub()
        probe.accept(input)
        #expect(probe.transform(input) === output)
        #expect(probe.optional(input) === optionalOutput)

        stub.verify { $0.accept(identical(to: input)) }
        stub.verify(returning: output) {
            $0.transform(identical(to: input))
        }
        stub.verify(returning: Optional(optionalOutput)) {
            $0.optional(any(using: Optional(input)))
        }
    }

    @Test func consumingCallsTransferOneReferenceOwnership() async throws {
        let result = try await exerciseConsumingReferenceArguments()
        #expect(result.sync.value == nil)
        #expect(result.async.value == nil)
        #expect(result.syncCounter.value == 1)
        #expect(result.asyncCounter.value == 1)
    }

    @Test func asyncAndFixedTypedThrowsPreserveDirectResults() async throws {
        _ = RealExternalReferenceAssociatedProbe()
        typealias Probe = any ExternalReferenceAssociatedProbe<
            ExternalReferenceAssociatedBox
        >
        let stub = try Stub<Probe>()
        let asyncInput = ExternalReferenceAssociatedBox(id: 10)
        let asyncOutput = ExternalReferenceAssociatedBox(id: 11)
        let successInput = ExternalReferenceAssociatedBox(id: 12)
        let successOutput = ExternalReferenceAssociatedBox(id: 13)
        let failureInput = ExternalReferenceAssociatedBox(id: 14)
        let asyncFailureInput = ExternalReferenceAssociatedBox(id: 15)

        await stub.when(returning: asyncOutput) {
            await $0.asynchronous(any(using: asyncInput))
        }.thenReturn(asyncOutput)
        stub.when(returning: successOutput) {
            try $0.throwing(identical(to: successInput))
        }.thenReturn(successOutput)
        stub.when(returning: successOutput) {
            try $0.throwing(identical(to: failureInput))
        }.thenThrow(ExternalReferenceFixedFailure(code: 16))
        await stub.when(returning: Optional(successOutput)) {
            try await $0.throwingAsynchronously(
                any(using: Optional(asyncFailureInput))
            )
        }.thenThrow(ExternalReferenceFixedFailure(code: 17))

        let probe: Probe = stub()
        #expect(await probe.asynchronous(asyncInput) === asyncOutput)
        #expect(try probe.throwing(successInput) === successOutput)
        let syncError = #expect(throws: ExternalReferenceFixedFailure.self) {
            _ = try probe.throwing(failureInput)
        }
        #expect(syncError == ExternalReferenceFixedFailure(code: 16))
        let asyncError = await #expect(
            throws: ExternalReferenceFixedFailure.self
        ) {
            _ = try await probe.throwingAsynchronously(asyncFailureInput)
        }
        #expect(asyncError == ExternalReferenceFixedFailure(code: 17))
    }

    @Test func associatedClassErrorsUseTheDirectErrorChannel() async throws {
        _ = RealExternalReferenceAssociatedFailureProbe()
        typealias Probe = any ExternalReferenceAssociatedFailureProbe<
            ExternalReferenceAssociatedFailure
        >
        let stub = try Stub<Probe>()
        let synchronous = try #require(stub.recorder.runtimeMethod(for: 0))
        let asynchronous = try #require(stub.recorder.runtimeMethod(for: 1))

        assertReferenceDependency(synchronous.effects.throwing.typedError?.dependency)
        assertReferenceDependency(asynchronous.effects.throwing.typedError?.dependency)
        #expect(synchronous.typedErrorUsesIndirectResultSlot == false)
        #expect(asynchronous.typedErrorUsesIndirectResultSlot == false)

        stub.when { try $0.load(equal(false)) }.thenReturn(40)
        stub.when { try $0.load(equal(true)) }.thenThrow(
            ExternalReferenceAssociatedFailure(code: 41)
        )
        await stub.when {
            try await $0.loadAsynchronously(equal(false))
        }.thenReturn(42)
        await stub.when {
            try await $0.loadAsynchronously(equal(true))
        }.thenThrow(ExternalReferenceAssociatedFailure(code: 43))

        let probe: Probe = stub()
        #expect(try probe.load(false) == 40)
        let syncError = #expect(
            throws: ExternalReferenceAssociatedFailure.self
        ) {
            _ = try probe.load(true)
        }
        #expect(syncError?.code == 41)
        #expect(try await probe.loadAsynchronously(false) == 42)
        let asyncError = await #expect(
            throws: ExternalReferenceAssociatedFailure.self
        ) {
            _ = try await probe.loadAsynchronously(true)
        }
        #expect(asyncError?.code == 43)
    }

    @Test func automaticClassErrorBindingCanDifferFromDiscoveryConformer() async throws {
        _ = RealExternalReferenceAssociatedFailureProbe()
        typealias Probe = any ExternalReferenceAssociatedFailureProbe<
            ExternalAlternateReferenceAssociatedFailure
        >
        let stub = try Stub<Probe>()
        let synchronous = try #require(stub.recorder.runtimeMethod(for: 0))
        let asynchronous = try #require(stub.recorder.runtimeMethod(for: 1))
        let expectedType = ObjectIdentifier(
            ExternalAlternateReferenceAssociatedFailure.self
        )

        #expect(synchronous.typedErrorType.map(ObjectIdentifier.init) == expectedType)
        #expect(asynchronous.typedErrorType.map(ObjectIdentifier.init) == expectedType)
        assertReferenceDependency(synchronous.effects.throwing.typedError?.dependency)
        assertReferenceDependency(asynchronous.effects.throwing.typedError?.dependency)
        #expect(synchronous.typedErrorUsesIndirectResultSlot == false)
        #expect(asynchronous.typedErrorUsesIndirectResultSlot == false)

        stub.when { try $0.load(equal(false)) }.thenReturn(50)
        stub.when { try $0.load(equal(true)) }.thenThrow(
            ExternalAlternateReferenceAssociatedFailure(code: 51)
        )
        await stub.when {
            try await $0.loadAsynchronously(equal(false))
        }.thenReturn(52)
        await stub.when {
            try await $0.loadAsynchronously(equal(true))
        }.thenThrow(ExternalAlternateReferenceAssociatedFailure(code: 53))

        let probe: Probe = stub()
        #expect(try probe.load(false) == 50)
        let synchronousError = try #require(
            #expect(throws: ExternalAlternateReferenceAssociatedFailure.self) {
                _ = try probe.load(true)
            }
        )
        #expect(synchronousError.code == 51)
        #expect(ObjectIdentifier(type(of: synchronousError)) == expectedType)
        #expect(try await probe.loadAsynchronously(false) == 52)
        let asynchronousError = try #require(
            await #expect(
                throws: ExternalAlternateReferenceAssociatedFailure.self
            ) {
                _ = try await probe.loadAsynchronously(true)
            }
        )
        #expect(asynchronousError.code == 53)
        #expect(ObjectIdentifier(type(of: asynchronousError)) == expectedType)
    }

    @Test func explicitSchemasRetainReferenceIdentity() async throws {
        typealias ProbeStub = Stub<
            any ExternalExplicitReferenceAssociatedProbe<
                ExternalReferenceAssociatedBox
            >
        >
        let value = ProbeStub.Requirement.Value.self
        let element = value.associatedType(named: "Element")
        let optional = value.optional(wrapping: element)
        let consuming = value.consumingAssociatedType(named: "Element")
        let stub = try ProbeStub(
            .method(element, returning: element),
            .method(optional, returning: optional),
            .method(consuming, returning: value.concrete(Void.self)),
            .method(element, returning: element, isAsync: true)
        )
        let input = ExternalReferenceAssociatedBox(id: 20)
        let output = ExternalReferenceAssociatedBox(id: 21)

        stub.when(returning: output) {
            $0.transform(any(using: input))
        }.thenReturn(output)
        stub.when(returning: Optional(output)) {
            $0.optional(any(using: Optional(input)))
        }.thenReturn(Optional(output))
        stub.when { $0.consume(any(using: input)) }.thenDoNothing()
        await stub.when(returning: output) {
            await $0.asynchronous(any(using: input))
        }.thenReturn(output)

        let probe = stub()
        #expect(probe.transform(input) === output)
        #expect(probe.optional(input) === output)
        probe.consume(input)
        #expect(await probe.asynchronous(input) === output)
    }

    @Test func explicitConcreteSchemaCannotEraseReferenceDependency() {
        _ = RealExternalReferenceAssociatedIdentityProbe()
        typealias ProbeStub = Stub<
            any ExternalReferenceAssociatedIdentityProbe<
                ExternalReferenceAssociatedBox
            >
        >

        expectStubError {
            _ = try ProbeStub(
                .method(
                    ExternalReferenceAssociatedBox.self,
                    returning: ExternalReferenceAssociatedBox.self
                )
            )
        } matching: { error in
            guard
                case .requirementMismatch(
                    _, let index, let expected, let actual
                ) = error
            else { return false }
            return index == 0
                && expected.contains("associated Element")
                && actual.contains("associated Element") == false
        }
    }

    @Test func explicitAssociatedClassErrorNeedsNoConformer() throws {
        typealias ProbeStub = Stub<
            any ExternalExplicitReferenceAssociatedFailureProbe<
                ExternalReferenceAssociatedFailure
            >
        >
        let stub = try ProbeStub(
            .method(
                returning: .concrete(Int.self),
                throwingAssociatedTypeNamed: "Failure"
            )
        )
        let method = try #require(stub.recorder.runtimeMethod(for: 0))

        assertReferenceDependency(method.effects.throwing.typedError?.dependency)
        #expect(method.typedErrorUsesIndirectResultSlot == false)
        stub.when { try $0.load() }.thenThrow(
            ExternalReferenceAssociatedFailure(code: 44)
        )
        let error = #expect(
            throws: ExternalReferenceAssociatedFailure.self
        ) {
            _ = try stub().load()
        }
        #expect(error?.code == 44)
    }

    @Test func callerBindingsSupportOnlyConcreteReferenceMetadata() throws {
        _ = RealExternalReferenceAssociatedProbe()
        typealias ProbeStub = Stub<any ExternalReferenceAssociatedProbe>
        let stub = try ProbeStub(
            associatedTypes: [
                .binding(
                    declaredBy: (any ExternalReferenceAssociatedProbe).self,
                    named: "Element",
                    to: ExternalReferenceAssociatedBox.self
                )
            ]
        )
        let direct = try #require(stub.recorder.runtimeMethod(for: 1))
        let optional = try #require(stub.recorder.runtimeMethod(for: 3))
        assertDirectReference(direct.arguments[0].value)
        assertDirectReference(direct.result)
        assertOptionalReference(optional.arguments[0].value)
        assertOptionalReference(optional.result)

        expectUnsupportedProtocolShape(
            containing: "must be bound to a concrete class type"
        ) {
            _ = try ProbeStub(
                associatedTypes: [
                    .binding(
                        declaredBy: (any ExternalReferenceAssociatedProbe).self,
                        named: "Element",
                        to: Int.self
                    )
                ]
            )
        }
        expectUnsupportedProtocolShape(
            containing: "value type or class existential"
        ) {
            _ = try ProbeStub(
                associatedTypes: [
                    .binding(
                        declaredBy: (any ExternalReferenceAssociatedProbe).self,
                        named: "Element",
                        to: (any ExternalReferenceAssociatedMarker).self
                    )
                ]
            )
        }
    }

    @Test func callerBoundReferenceInputsInvokeEndToEnd() async throws {
        _ = RealExternalReferenceAssociatedProbe()
        typealias Probe = any ExternalReferenceAssociatedProbe
        let stub = try Stub<Probe>(
            associatedTypes: [
                .binding(
                    declaredBy: (any ExternalReferenceAssociatedProbe).self,
                    named: "Element",
                    to: ExternalReferenceAssociatedBox.self
                )
            ]
        )
        let directInput = ExternalReferenceAssociatedBox(id: 30)
        let directOutput = ExternalReferenceAssociatedBox(id: 31)
        let optionalInput = ExternalReferenceAssociatedBox(id: 32)
        let optionalOutput = ExternalReferenceAssociatedBox(id: 33)
        let consumingInput = ExternalReferenceAssociatedBox(id: 34)
        let asynchronousInput = ExternalReferenceAssociatedBox(id: 35)
        let asynchronousOutput = ExternalReferenceAssociatedBox(id: 36)
        let asynchronousConsumingInput = ExternalReferenceAssociatedBox(id: 37)

        stub.when(returning: directOutput) {
            callerBoundTransform(
                $0,
                directInput,
                recordsMatcher: true
            )
        }.thenReturn(directOutput)
        stub.when(returning: Optional(optionalOutput)) {
            callerBoundOptional(
                $0,
                optionalInput,
                recordsMatcher: true
            )
        }.thenReturn(Optional(optionalOutput))
        stub.when {
            callerBoundConsume(
                $0,
                consumingInput,
                recordsMatcher: true
            )
        }.thenDoNothing()
        await stub.when(returning: asynchronousOutput) {
            await callerBoundAsynchronous(
                $0,
                asynchronousInput,
                recordsMatcher: true
            )
        }.thenReturn(asynchronousOutput)
        await stub.when {
            await callerBoundConsumeAsynchronously(
                $0,
                asynchronousConsumingInput,
                recordsMatcher: true
            )
        }.thenDoNothing()

        let probe: Probe = stub()
        #expect(
            callerBoundTransform(
                probe,
                directInput,
                recordsMatcher: false
            ) === directOutput
        )
        #expect(
            callerBoundOptional(
                probe,
                optionalInput,
                recordsMatcher: false
            ) === optionalOutput
        )
        callerBoundConsume(
            probe,
            consumingInput,
            recordsMatcher: false
        )
        #expect(
            await callerBoundAsynchronous(
                probe,
                asynchronousInput,
                recordsMatcher: false
            ) === asynchronousOutput
        )
        await callerBoundConsumeAsynchronously(
            probe,
            asynchronousConsumingInput,
            recordsMatcher: false
        )
    }

    @Test func otherReferenceDependentShapesRemainFailClosed() {
        _ = RealExternalUnsupportedReferenceArrayProbe()
        _ = RealExternalUnsupportedNestedOptionalReferenceProbe()

        expectUnsupportedProtocolShape(
            containing: "Only direct values and one Optional layer"
        ) {
            _ = try Stub<
                any ExternalUnsupportedReferenceArrayProbe<
                    ExternalReferenceAssociatedBox
                >
            >()
        }
        expectUnsupportedProtocolShape(
            containing: "Only direct values and one Optional layer"
        ) {
            _ = try Stub<
                any ExternalUnsupportedNestedOptionalReferenceProbe<
                    ExternalReferenceAssociatedBox
                >
            >()
        }
    }
}

private final class ReferenceAssociatedLifetimeBox: @unchecked Sendable {
    private let deinitCounter: LockedCounter

    init(deinitCounter: LockedCounter) {
        self.deinitCounter = deinitCounter
    }

    deinit {
        deinitCounter.increment()
    }
}

private func exerciseConsumingReferenceArguments() async throws -> (
    sync: WeakReference<ReferenceAssociatedLifetimeBox>,
    async: WeakReference<ReferenceAssociatedLifetimeBox>,
    syncCounter: LockedCounter,
    asyncCounter: LockedCounter
) {
    _ = RealExternalReferenceAssociatedProbe()
    typealias Probe = any ExternalReferenceAssociatedProbe<
        ReferenceAssociatedLifetimeBox
    >
    let stub = try Stub<Probe>()
    let placeholderCounter = LockedCounter()
    let placeholder = ReferenceAssociatedLifetimeBox(
        deinitCounter: placeholderCounter
    )
    stub.when { $0.consume(any(using: placeholder)) }.thenDoNothing()
    await stub.when {
        await $0.consumeAsynchronously(any(using: placeholder))
    }.thenDoNothing()

    let probe: Probe = stub()
    let syncCounter = LockedCounter()
    var syncValue: ReferenceAssociatedLifetimeBox? =
        ReferenceAssociatedLifetimeBox(deinitCounter: syncCounter)
    let weakSync = WeakReference(syncValue)
    probe.consume(try #require(syncValue))
    syncValue = nil
    #expect(weakSync.value != nil)

    let asyncCounter = LockedCounter()
    var asyncValue: ReferenceAssociatedLifetimeBox? =
        ReferenceAssociatedLifetimeBox(deinitCounter: asyncCounter)
    let weakAsync = WeakReference(asyncValue)
    await probe.consumeAsynchronously(try #require(asyncValue))
    asyncValue = nil
    #expect(weakAsync.value != nil)

    stub.verify { $0.consume(any(using: placeholder)) }
    await stub.verify {
        await $0.consumeAsynchronously(any(using: placeholder))
    }
    return (weakSync, weakAsync, syncCounter, asyncCounter)
}

private func assertDirectReference(
    _ value: WitnessValueDescriptor,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    assertReferenceDependency(value.dependency, sourceLocation: sourceLocation)
    assertOneWord(value.layout, sourceLocation: sourceLocation)
}

private func assertOptionalReference(
    _ value: WitnessValueDescriptor,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .optional(let wrapped) = value.dependency else {
        Issue.record(
            "Expected an Optional dependency.",
            sourceLocation: sourceLocation
        )
        return
    }
    assertReferenceDependency(wrapped, sourceLocation: sourceLocation)
    assertOneWord(value.layout, sourceLocation: sourceLocation)
}

private func assertReferenceDependency(
    _ dependency: WitnessValueDependency?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .associatedType(let reference) = dependency else {
        Issue.record(
            "Expected an associated-type dependency.",
            sourceLocation: sourceLocation
        )
        return
    }
    #expect(reference.usesReferenceABI, sourceLocation: sourceLocation)
    #expect(
        dependency?.usesOpaqueValueWitnessConvention == false,
        sourceLocation: sourceLocation
    )
}

private func assertOneWord(
    _ layout: ABIClass,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .integer(words: 1) = layout else {
        Issue.record(
            "Expected one direct general-purpose word.",
            sourceLocation: sourceLocation
        )
        return
    }
}

// Reopen the unbound existential, then retype the concrete class through the
// associated metadata accessor installed in its fabricated witness table. A
// wrong caller binding would make these downcasts trap before the call returns.
private func callerBoundTransform<P, Element>(
    _ probe: P,
    _ value: Element,
    recordsMatcher: Bool
) -> Element
where P: ExternalReferenceAssociatedProbe, Element: AnyObject {
    let boundValue = unsafeDowncast(value, to: P.Element.self)
    let argument = recordsMatcher ? any(using: boundValue) : boundValue
    return unsafeDowncast(probe.transform(argument), to: Element.self)
}

private func callerBoundOptional<P, Element>(
    _ probe: P,
    _ value: Element?,
    recordsMatcher: Bool
) -> Element?
where P: ExternalReferenceAssociatedProbe, Element: AnyObject {
    let boundValue = value.map { unsafeDowncast($0, to: P.Element.self) }
    let argument = recordsMatcher ? any(using: boundValue) : boundValue
    return probe.optional(argument).map {
        unsafeDowncast($0, to: Element.self)
    }
}

private func callerBoundConsume<P, Element>(
    _ probe: P,
    _ value: Element,
    recordsMatcher: Bool
) where P: ExternalReferenceAssociatedProbe, Element: AnyObject {
    let boundValue = unsafeDowncast(value, to: P.Element.self)
    let argument = recordsMatcher ? any(using: boundValue) : boundValue
    probe.consume(argument)
}

private func callerBoundAsynchronous<P, Element>(
    _ probe: P,
    _ value: Element,
    recordsMatcher: Bool
) async -> Element
where P: ExternalReferenceAssociatedProbe, Element: AnyObject {
    let boundValue = unsafeDowncast(value, to: P.Element.self)
    let argument = recordsMatcher ? any(using: boundValue) : boundValue
    return unsafeDowncast(
        await probe.asynchronous(argument),
        to: Element.self
    )
}

private func callerBoundConsumeAsynchronously<P, Element>(
    _ probe: P,
    _ value: Element,
    recordsMatcher: Bool
) async
where P: ExternalReferenceAssociatedProbe, Element: AnyObject {
    let boundValue = unsafeDowncast(value, to: P.Element.self)
    let argument = recordsMatcher ? any(using: boundValue) : boundValue
    await probe.consumeAsynchronously(argument)
}
