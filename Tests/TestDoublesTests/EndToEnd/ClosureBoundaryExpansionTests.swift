import TestDoubles
import TestDoublesFixtures
import Testing

private func replaceClosure(
    _ closure: inout ExternalContainerClosure,
    with replacement: @escaping ExternalContainerClosure
) {
    closure = replacement
}

// swiftlint:disable:next type_body_length
struct ClosureBoundaryExpansionTests {
    @Test func cFunctionPointersRoundTrip() throws {
        _ = RealExternalFunctionConventionService()
        let cIdentity: ExternalCFunction = externalCIncrement
        let cResult: ExternalCFunction = externalCDouble
        let cCaptor = ArgumentCaptor<ExternalCFunction>()
        let stub = try Stub<any ExternalFunctionConventionService>()

        stub.when(returning: cIdentity) {
            $0.cFunction(cCaptor.capture(using: cIdentity))
        }.thenReturn(cResult)

        #expect(stub().cFunction(cIdentity)(21) == 42)
        let capturedC = try #require(cCaptor.first)
        #expect(capturedC(41) == 42)
    }

    #if canImport(ObjectiveC)
        @Test func capturedBlockFunctionsRetainTheirContexts() throws {
            _ = RealExternalFunctionConventionService()
            let identity: ExternalBlockFunction = { $0 }
            let captured = Int32(21)
            let result: ExternalBlockFunction = { $0 + captured }
            let captor = ArgumentCaptor<ExternalBlockFunction>()
            let stub = try Stub<any ExternalFunctionConventionService>()
            stub.when(returning: identity) {
                $0.blockFunction(captor.capture(using: identity))
            }.thenReturn(result)

            let returned = stub().blockFunction { $0 * 2 }

            #expect(returned(21) == 42)
            let capturedBlock = try #require(captor.first)
            #expect(capturedBlock(21) == 42)
        }
    #endif

    @Test func optionalClosuresPreserveTheirPayloads() throws {
        _ = RealExternalClosureContainerService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let result: ExternalContainerClosure = { "\($0 * 2)!" }
        let stub = try Stub<any ExternalClosureContainerService>()

        stub.when(returning: identity) {
            $0.optional(any(using: identity))
        }.thenReturn(result)

        #expect(stub().optional(identity)?(21) == "42!")
    }

    @Test func arraysOfClosuresPreserveTheirPayloads() throws {
        _ = RealExternalClosureContainerService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let result: ExternalContainerClosure = { "\($0 * 2)!" }
        let stub = try Stub<any ExternalClosureContainerService>()

        stub.when(returning: [identity]) {
            $0.array(any(using: [identity]))
        }.thenReturn([result])

        #expect(stub().array([identity]).first?(21) == "42!")
    }

    @Test func tuplesContainingClosuresPreserveTheirPayloads() throws {
        _ = RealExternalClosureContainerService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let result: ExternalContainerClosure = { "\($0 * 2)!" }
        let tuplePlaceholder: ExternalClosureTuple = ("placeholder", identity)
        let tupleResult: ExternalClosureTuple = ("tuple", result)
        let stub = try Stub<any ExternalClosureContainerService>()

        stub.when(returning: tuplePlaceholder) {
            $0.tuple(any(using: tuplePlaceholder))
        }.thenReturn(tupleResult)

        let tuple = stub().tuple(("input", identity))
        #expect(tuple.label == "tuple")
        #expect(tuple.transform(21) == "42!")
    }

    @Test func nominalValuesContainingClosuresPreserveTheirPayloads() throws {
        _ = RealExternalClosureContainerService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let result: ExternalContainerClosure = { "\($0 * 2)!" }
        let boxPlaceholder = ExternalClosureBox(label: "placeholder", transform: identity)
        let boxResult = ExternalClosureBox(label: "box", transform: result)
        let stub = try Stub<any ExternalClosureContainerService>()

        stub.when(returning: boxPlaceholder) {
            $0.nominal(any(using: boxPlaceholder))
        }.thenReturn(boxResult)

        let box = stub().nominal(boxPlaceholder)
        #expect(box.label == "box")
        #expect(box.transform(21) == "42!")
    }

    @Test func nestedNonescapingCallbacksStayWithinOuterInvocation() throws {
        _ = RealExternalNestedNonescapingClosureService()
        let identity: ExternalNestedNonescapingClosure = { callback in
            let captured = callback(0)
            return { $0 + captured }
        }
        let result: ExternalNestedNonescapingClosure = { callback in
            let captured = callback(21)
            return { _ in captured }
        }
        let captor = ArgumentCaptor<ExternalNestedNonescapingClosure>()
        let stub = try Stub<any ExternalNestedNonescapingClosureService>()
        stub.when(returning: identity) {
            $0.nested(captor.capture(using: identity))
        }.thenReturn(result)

        let returned = stub().nested { callback in
            let captured = callback(0)
            return { $0 + captured }
        }
        #expect(returned { $0 * 2 }(0) == 42)
        let captured = try #require(captor.first)
        #expect(captured { $0 * 2 }(21) == 21)
    }

    @Test func isolatedParametersPreserveActorExecution() async throws {
        _ = RealExternalIsolatedParameterClosureService()
        let identity: ExternalIsolatedParameterClosure = { actor, value in
            actor.add(value)
        }
        let result: ExternalIsolatedParameterClosure = { actor, value in
            actor.add(value * 2)
        }
        let captor = ArgumentCaptor<ExternalIsolatedParameterClosure>()
        let stub = try Stub<any ExternalIsolatedParameterClosureService>()
        stub.when(returning: identity) {
            $0.isolatedParameter(captor.capture(using: identity))
        }.thenReturn(result)

        let worker = ExternalClosureWorker()
        let returned = stub().isolatedParameter(identity)
        #expect(await returned(worker, 21) == 42)
        let captured = try #require(captor.first)
        #expect(await captured(worker, 1) == 43)
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func largeTypedErrorsUseIndirectInnerTransport() throws {
        _ = RealExternalIndirectTypedThrowingClosureService()
        let failure = ExternalLargeClosureError(
            first: 1,
            second: 2,
            third: 3,
            fourth: 4
        )
        let identity: ExternalIndirectTypedThrowingClosure = { "\($0)" }
        let result: ExternalIndirectTypedThrowingClosure = {
            value throws(ExternalLargeClosureError) in
            guard value != 0 else { throw failure }
            return "\(value * 2)!"
        }
        let stub = try Stub<any ExternalIndirectTypedThrowingClosureService>()
        stub.when(returning: identity) {
            $0.typedThrowing(any(using: identity))
        }.thenReturn(result)

        let returned = stub().typedThrowing(identity)
        #expect(try returned(21) == "42!")
        #expect(throws: failure) {
            try returned(0)
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func asyncIndirectResultsAndTypedErrorsRoundTripBothClosureDirections() async throws {
        _ = RealExternalIndirectTypedThrowingClosureService()
        let failure = ExternalLargeClosureError(
            first: 5,
            second: 6,
            third: 7,
            fourth: 8
        )
        let placeholder: ExternalAsyncIndirectTypedThrowingClosure = { value in
            ExternalNullaryLargeResult(
                first: value,
                second: 0,
                third: 0,
                fourth: 0,
                fifth: 0
            )
        }
        let input: ExternalAsyncIndirectTypedThrowingClosure = {
            value async throws(ExternalLargeClosureError) in
            await Task.yield()
            guard value != 0 else { throw failure }
            return ExternalNullaryLargeResult(
                first: value,
                second: value + 1,
                third: value + 2,
                fourth: value + 3,
                fifth: value + 4
            )
        }
        let result: ExternalAsyncIndirectTypedThrowingClosure = {
            value async throws(ExternalLargeClosureError) in
            await Task.yield()
            guard value != 0 else { throw failure }
            return ExternalNullaryLargeResult(
                first: value * 2,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
        let captor = ArgumentCaptor<ExternalAsyncIndirectTypedThrowingClosure>()
        let stub = try Stub<any ExternalIndirectTypedThrowingClosureService>()
        stub.when(returning: placeholder) {
            $0.asyncTypedThrowing(captor.capture(using: placeholder))
        }.thenReturn(result)

        let returned = stub().asyncTypedThrowing(input)
        #expect(try await returned(21).first == 42)
        await #expect(throws: failure) {
            _ = try await returned(0)
        }

        let captured = try #require(captor.first)
        #expect(try await captured(21).fifth == 25)
        await #expect(throws: failure) {
            _ = try await captured(0)
        }
    }

    @Test func modifyCoroutineReabstractsClosureStorageBothWays() throws {
        _ = RealExternalMutableClosureService(transform: { "\($0)" })
        let initial: ExternalContainerClosure = { "\($0)" }
        let replacement: ExternalContainerClosure = { "\($0 * 2)!" }
        let captor = ArgumentCaptor<ExternalContainerClosure>()
        let stub = try Stub<any ExternalMutableClosureService>()
        stub.when(returning: initial) { $0.transform }.thenReturn(initial)
        stub.when {
            $0.transform = captor.capture(using: initial)
        }.thenReturn(())

        var value: any ExternalMutableClosureService = stub()
        replaceClosure(&value.transform, with: replacement)

        let captured = try #require(captor.first)
        #expect(captured(21) == "42!")
    }

    @Test func initializerClosureArgumentsReachTheRecorder() throws {
        _ = RealExternalClosureInitializerService(transform: { "\($0)" })
        let identity: ExternalContainerClosure = { "\($0)" }
        let captor = ArgumentCaptor<ExternalContainerClosure>()
        let stub = try Stub<any ExternalClosureInitializerService>()
        stub.when(initializer: {
            type(of: $0).init(
                transform: captor.capture(using: identity)
            )
        }).thenInitialize()
        stub.when { $0.apply(any()) }.thenReturn("stubbed")

        let seed: any ExternalClosureInitializerService = stub()
        _ = type(of: seed).init(transform: { "\($0 * 2)!" })

        let captured = try #require(captor.first)
        #expect(captured(21) == "42!")
    }

    @Test func closureValuesWorkInStaticVariadicAndSubscriptRequirements() throws {
        _ = RealExternalClosureRequirementPositionsService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let result: ExternalContainerClosure = { "\($0 * 2)!" }
        let stub = try Stub<any ExternalClosureRequirementPositionsService>()

        stub.when(returning: identity) {
            type(of: $0).staticTransform(any(using: identity))
        }.thenReturn(result)
        stub.when(returning: [identity]) {
            $0.variadic(any(using: identity))
        }.thenReturn([result])
        stub.when(returning: identity) {
            $0[any(using: identity)]
        }.thenReturn(result)

        let value: any ExternalClosureRequirementPositionsService = stub()
        #expect(type(of: value).staticTransform(identity)(21) == "42!")
        #expect(value.variadic(identity).first?(21) == "42!")
        #expect(value[identity](21) == "42!")
    }

    @Test func boundAssociatedClosureValuesFailBeforeTransport() {
        _ = RealExternalAssociatedClosureService()
        #expect(throws: StubError.self) {
            try Stub<
                any ExternalAssociatedClosureService<ExternalContainerClosure>
            >()
        }
    }

    @Test func consumingClosureParametersFailClosedDuringConstruction() {
        _ = RealExternalConsumingClosureParameterService()
        #expect(throws: StubError.self) {
            try Stub<any ExternalConsumingClosureParameterService>()
        }
    }

    @Test func borrowingClosureParametersReachTypedHandlers() throws {
        _ = RealExternalBorrowingClosureParameterService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let stub = try Stub<any ExternalBorrowingClosureParameterService>()

        stub.when {
            $0.borrow(any(using: identity))
        }.then { (closure: ExternalContainerClosure) in closure(21) + "?" }

        #expect(stub().borrow { "\($0 * 2)" } == "42?")
    }

    @Test func escapingAutoclosureParametersReachTypedHandlers() throws {
        _ = RealExternalAutoclosureParameterService()
        let integerPlaceholder: @Sendable () -> Int = { 0 }
        let floatingPlaceholder: @Sendable () -> Double = { 0 }
        let aggregatePlaceholder: @Sendable () -> ExternalNullaryAggregate = {
            ExternalNullaryAggregate(label: "", count: 0, enabled: false)
        }
        let largePlaceholder: @Sendable () -> ExternalNullaryLargeResult = {
            ExternalNullaryLargeResult(
                first: 0,
                second: 0,
                third: 0,
                fourth: 0,
                fifth: 0
            )
        }
        let stub = try Stub<any ExternalAutoclosureParameterService>()

        stub.when {
            let matched = any(using: integerPlaceholder)
            return $0.evaluate(matched())
        }.then { (value: @Sendable () -> Int) in value() * 2 }
        stub.when {
            let matched = any(using: floatingPlaceholder)
            return $0.evaluateFloating(matched())
        }.then { (value: @Sendable () -> Double) in value() + 0.5 }
        stub.when {
            let matched = any(using: aggregatePlaceholder)
            return $0.evaluateAggregate(matched())
        }.then { (value: @Sendable () -> ExternalNullaryAggregate) in value() }
        stub.when {
            let matched = any(using: largePlaceholder)
            return $0.evaluateLarge(matched())
        }.then { (value: @Sendable () -> ExternalNullaryLargeResult) in value() }

        #expect(stub().evaluate(21) == 42)
        #expect(stub().evaluateFloating(13) == 13.5)

        let aggregate = ExternalNullaryAggregate(
            label: "direct",
            count: 3,
            enabled: true
        )
        #expect(stub().evaluateAggregate(aggregate) == aggregate)

        let large = ExternalNullaryLargeResult(
            first: 1,
            second: 2,
            third: 3,
            fourth: 4,
            fifth: 5
        )
        #expect(stub().evaluateLarge(large) == large)
    }

    @Test func dynamicBridgeCoversOneThroughSixMixedParameters() throws {
        _ = RealExternalDynamicArityClosureService()
        let widePlaceholder: ExternalWideUnaryClosure = { $0.label }
        let binaryPlaceholder: ExternalMixedBinaryClosure = { value, _ in
            ExternalNullaryAggregate(label: "", count: value, enabled: false)
        }
        let ternaryPlaceholder: ExternalMixedTernaryClosure = { _, value, _ in
            Double(value)
        }
        let quaternaryPlaceholder: ExternalMixedQuaternaryClosure = {
            value, _, _, _ in "\(value)"
        }
        let quinaryPlaceholder: ExternalMixedQuinaryClosure = {
            value, _, _, _, _ in "\(value)"
        }
        let senaryPlaceholder: ExternalSenaryClosure = {
            $0 + $1 + $2 + $3 + $4 + $5
        }
        let higherOrderPlaceholder: ExternalOptionalHigherOrderClosure = {
            closure, _ in closure
        }
        let higherOrderResult: ExternalOptionalHigherOrderClosure = {
            (
                closure: ExternalContainerClosure?, offset: Int
            )
                -> ExternalContainerClosure? in
            guard let closure else { return nil }
            let transformed: ExternalContainerClosure = { value in
                closure(value + offset)
            }
            return transformed
        }
        let wideCaptor = ArgumentCaptor<ExternalWideUnaryClosure>()
        let binaryCaptor = ArgumentCaptor<ExternalMixedBinaryClosure>()
        let ternaryCaptor = ArgumentCaptor<ExternalMixedTernaryClosure>()
        let quaternaryCaptor = ArgumentCaptor<ExternalMixedQuaternaryClosure>()
        let quinaryCaptor = ArgumentCaptor<ExternalMixedQuinaryClosure>()
        let senaryCaptor = ArgumentCaptor<ExternalSenaryClosure>()
        let higherOrderCaptor =
            ArgumentCaptor<ExternalOptionalHigherOrderClosure>()
        let stub = try Stub<any ExternalDynamicArityClosureService>()

        stub.when(returning: widePlaceholder) {
            $0.wideUnary(wideCaptor.capture(using: widePlaceholder))
        }.thenReturn { value in
            "\(value.label)-\(value.first + value.second + value.third + value.fourth)"
        }
        stub.when(returning: binaryPlaceholder) {
            $0.mixedBinary(binaryCaptor.capture(using: binaryPlaceholder))
        }.thenReturn { value, floating in
            ExternalNullaryAggregate(
                label: "\(floating)",
                count: value * 2,
                enabled: true
            )
        }
        stub.when(returning: ternaryPlaceholder) {
            $0.mixedTernary(ternaryCaptor.capture(using: ternaryPlaceholder))
        }.thenReturn { floating, value, label in
            Double(floating) + Double(value + label.count)
        }
        stub.when(returning: quaternaryPlaceholder) {
            $0.mixedQuaternary(
                quaternaryCaptor.capture(using: quaternaryPlaceholder)
            )
        }.thenReturn { value, floating, enabled, label in
            "\(label)-\(value)-\(floating)-\(enabled)"
        }
        stub.when(returning: quinaryPlaceholder) {
            $0.mixedQuinary(
                quinaryCaptor.capture(using: quinaryPlaceholder)
            )
        }.thenReturn { value, floating, enabled, short, label in
            "\(label)-\(value)-\(floating)-\(enabled)-\(short)"
        }
        stub.when(returning: senaryPlaceholder) {
            $0.senary(senaryCaptor.capture(using: senaryPlaceholder))
        }.thenReturn { first, second, third, fourth, fifth, sixth in
            first * second * third * fourth * fifth * sixth
        }
        stub.when(returning: higherOrderPlaceholder) {
            $0.optionalHigherOrder(
                higherOrderCaptor.capture(using: higherOrderPlaceholder)
            )
        }.thenReturn(higherOrderResult)

        let value: any ExternalDynamicArityClosureService = stub()
        let wideInput: ExternalWideUnaryClosure = { $0.label.uppercased() }
        let wide = value.wideUnary(wideInput)
        #expect(
            wide(
                ExternalWideClosureArgument(
                    label: "wide",
                    first: 1,
                    second: 2,
                    third: 3,
                    fourth: 4
                )
            ) == "wide-10"
        )
        #expect(
            value.mixedBinary(binaryPlaceholder)(21, 1.5)
                == ExternalNullaryAggregate(
                    label: "1.5",
                    count: 42,
                    enabled: true
                )
        )
        #expect(value.mixedTernary(ternaryPlaceholder)(1.5, 20, "!") == 22.5)
        #expect(
            value.mixedQuaternary(quaternaryPlaceholder)(21, 1.5, true, "mix")
                == "mix-21-1.5-true"
        )
        #expect(
            value.mixedQuinary(quinaryPlaceholder)(21, 1.5, true, 2.5, "five")
                == "five-21-1.5-true-2.5"
        )
        #expect(value.senary(senaryPlaceholder)(1, 2, 3, 4, 5, 6) == 720)
        let higherOrderInput: ExternalOptionalHigherOrderClosure = {
            (
                closure: ExternalContainerClosure?, multiplier: Int
            )
                -> ExternalContainerClosure? in
            guard let closure else { return nil }
            let transformed: ExternalContainerClosure = { value in
                closure(value * multiplier)
            }
            return transformed
        }
        let base: ExternalContainerClosure = { "value-\($0)" }
        let returnedHigherOrder = value.optionalHigherOrder(higherOrderInput)
        #expect(returnedHigherOrder(base, 2)?(20) == "value-22")
        #expect(returnedHigherOrder(nil, 2) == nil)

        let capturedWide = try #require(wideCaptor.first)
        let capturedBinary = try #require(binaryCaptor.first)
        let capturedTernary = try #require(ternaryCaptor.first)
        let capturedQuaternary = try #require(quaternaryCaptor.first)
        let capturedQuinary = try #require(quinaryCaptor.first)
        let capturedSenary = try #require(senaryCaptor.first)
        let capturedHigherOrder = try #require(higherOrderCaptor.first)
        #expect(
            capturedWide(
                ExternalWideClosureArgument(
                    label: "input",
                    first: 0,
                    second: 0,
                    third: 0,
                    fourth: 0
                )
            ) == "INPUT"
        )
        #expect(capturedBinary(7, 0).count == 7)
        #expect(capturedTernary(0, 7, "") == 7)
        #expect(capturedQuaternary(7, 0, false, "") == "7")
        #expect(capturedQuinary(7, 0, false, 0, "") == "7")
        #expect(capturedSenary(1, 2, 3, 4, 5, 6) == 21)
        #expect(capturedHigherOrder(base, 2)?(20) == "value-40")
        #expect(capturedHigherOrder(nil, 2) == nil)
    }

    @Test func dynamicBridgePreservesUntypedErrorsAcrossFourParameters() throws {
        _ = RealExternalDynamicArityClosureService()
        let placeholder: ExternalThrowingQuaternaryClosure = {
            value, _, _, _ in "\(value)"
        }
        let input: ExternalThrowingQuaternaryClosure = {
            value, _, enabled, _ in
            guard enabled else {
                throw ExternalDynamicClosureError.rejected(value)
            }
            return "input-\(value)"
        }
        let captor = ArgumentCaptor<ExternalThrowingQuaternaryClosure>()
        let stub = try Stub<any ExternalDynamicArityClosureService>()
        stub.when(returning: placeholder) {
            $0.throwingQuaternary(captor.capture(using: placeholder))
        }.thenReturn { value, floating, enabled, label in
            guard enabled else {
                throw ExternalDynamicClosureError.rejected(value)
            }
            return "\(label)-\(value)-\(floating)"
        }

        let returned = stub().throwingQuaternary(input)
        #expect(try returned(21, 1.5, true, "ok") == "ok-21-1.5")
        #expect(throws: ExternalDynamicClosureError.rejected(21)) {
            try returned(21, 1.5, false, "no")
        }

        let captured = try #require(captor.first)
        #expect(try captured(7, 0, true, "") == "input-7")
        #expect(throws: ExternalDynamicClosureError.rejected(7)) {
            try captured(7, 0, false, "")
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func dynamicBridgePreservesTypedErrorsAcrossMixedRegisters() throws {
        _ = RealExternalDynamicTypedClosureService()
        let quaternaryPlaceholder: ExternalTypedQuaternaryClosure = {
            value, _, _, _ in "\(value)"
        }
        let quaternaryInput: ExternalTypedQuaternaryClosure = {
            value, _, enabled, _ throws(ExternalDynamicClosureError) in
            guard enabled else {
                throw ExternalDynamicClosureError.rejected(value)
            }
            return "input-\(value)"
        }
        let quaternaryResult: ExternalTypedQuaternaryClosure = {
            value, floating, enabled, label throws(ExternalDynamicClosureError) in
            guard enabled else {
                throw ExternalDynamicClosureError.rejected(value)
            }
            return "\(label)-\(value)-\(floating)"
        }
        let quaternaryCaptor =
            ArgumentCaptor<ExternalTypedQuaternaryClosure>()

        let mixedFailure = ExternalMixedClosureError(code: 7, ratio: 1.5)
        let mixedPlaceholder: ExternalMixedTypedBinaryClosure = {
            value, _ in
            ExternalNullaryAggregate(
                label: "placeholder",
                count: value,
                enabled: true
            )
        }
        let mixedInput: ExternalMixedTypedBinaryClosure = {
            value, ratio throws(ExternalMixedClosureError) in
            guard value >= 0 else { throw mixedFailure }
            return ExternalNullaryAggregate(
                label: "input",
                count: value,
                enabled: ratio > 0
            )
        }
        let mixedResult: ExternalMixedTypedBinaryClosure = {
            value, ratio throws(ExternalMixedClosureError) in
            guard value >= 0 else { throw mixedFailure }
            return ExternalNullaryAggregate(
                label: "returned",
                count: value * 2,
                enabled: ratio > 0
            )
        }
        let mixedCaptor = ArgumentCaptor<ExternalMixedTypedBinaryClosure>()
        let stub = try Stub<any ExternalDynamicTypedClosureService>()

        stub.when(returning: quaternaryPlaceholder) {
            $0.quaternary(
                quaternaryCaptor.capture(using: quaternaryPlaceholder)
            )
        }.thenReturn(quaternaryResult)
        stub.when(returning: mixedPlaceholder) {
            $0.mixedError(mixedCaptor.capture(using: mixedPlaceholder))
        }.thenReturn(mixedResult)

        let value: any ExternalDynamicTypedClosureService = stub()
        let returnedQuaternary = value.quaternary(quaternaryInput)
        #expect(try returnedQuaternary(21, 1.5, true, "ok") == "ok-21-1.5")
        #expect(throws: ExternalDynamicClosureError.rejected(21)) {
            try returnedQuaternary(21, 1.5, false, "no")
        }
        let capturedQuaternary = try #require(quaternaryCaptor.first)
        #expect(try capturedQuaternary(7, 0, true, "") == "input-7")
        #expect(throws: ExternalDynamicClosureError.rejected(7)) {
            try capturedQuaternary(7, 0, false, "")
        }

        let returnedMixed = value.mixedError(mixedInput)
        #expect(
            try returnedMixed(21, 1).count == 42
        )
        #expect(throws: mixedFailure) {
            try returnedMixed(-1, 0)
        }
        let capturedMixed = try #require(mixedCaptor.first)
        #expect(try capturedMixed(7, 1).label == "input")
        #expect(throws: mixedFailure) {
            try capturedMixed(-1, 0)
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func typedErrorsRemainDistinctFromIndirectSuccessStorage() throws {
        _ = RealExternalDynamicTypedClosureService()
        let placeholder: ExternalTypedIndirectSuccessClosure = { value in
            ExternalNullaryLargeResult(
                first: value,
                second: 0,
                third: 0,
                fourth: 0,
                fifth: 0
            )
        }
        let input: ExternalTypedIndirectSuccessClosure = {
            value throws(ExternalDynamicClosureError) in
            guard value != 0 else {
                throw ExternalDynamicClosureError.rejected(value)
            }
            return ExternalNullaryLargeResult(
                first: value,
                second: value + 1,
                third: value + 2,
                fourth: value + 3,
                fifth: value + 4
            )
        }
        let result: ExternalTypedIndirectSuccessClosure = {
            value throws(ExternalDynamicClosureError) in
            guard value != 0 else {
                throw ExternalDynamicClosureError.rejected(value)
            }
            return ExternalNullaryLargeResult(
                first: value * 2,
                second: 2,
                third: 3,
                fourth: 4,
                fifth: 5
            )
        }
        let captor = ArgumentCaptor<ExternalTypedIndirectSuccessClosure>()
        let stub = try Stub<any ExternalDynamicTypedClosureService>()
        stub.when(returning: placeholder) {
            $0.indirectSuccess(captor.capture(using: placeholder))
        }.thenReturn(result)

        let returned = stub().indirectSuccess(input)
        #expect(try returned(21).first == 42)
        #expect(throws: ExternalDynamicClosureError.rejected(0)) {
            try returned(0)
        }
        let captured = try #require(captor.first)
        #expect(try captured(21).fifth == 25)
        #expect(throws: ExternalDynamicClosureError.rejected(0)) {
            try captured(0)
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func typedThrowsComposesWithNullaryAndHigherOrderClosures() throws {
        _ = RealExternalDynamicTypedClosureService()
        let nullaryFailure: ExternalDynamicClosureError = .rejected(0)
        let nullaryPlaceholder: ExternalTypedNullaryClosure = { 0 }
        let nullaryInput: ExternalTypedNullaryClosure = {
            () throws(ExternalDynamicClosureError) in
            throw nullaryFailure
        }
        let nullaryResult: ExternalTypedNullaryClosure = {
            () throws(ExternalDynamicClosureError) in
            throw nullaryFailure
        }
        let nullaryCaptor = ArgumentCaptor<ExternalTypedNullaryClosure>()

        let identity: ExternalContainerClosure = { "value-\($0)" }
        let higherPlaceholder: ExternalTypedHigherOrderClosure = {
            closure, _ in closure
        }
        let higherInput: ExternalTypedHigherOrderClosure = {
            closure, multiplier throws(ExternalDynamicClosureError) in
            guard multiplier != 0 else {
                throw ExternalDynamicClosureError.rejected(multiplier)
            }
            return { value in "input-\(closure(value * multiplier))" }
        }
        let higherResult: ExternalTypedHigherOrderClosure = {
            closure, multiplier throws(ExternalDynamicClosureError) in
            guard multiplier != 0 else {
                throw ExternalDynamicClosureError.rejected(multiplier)
            }
            return { value in "returned-\(closure(value * multiplier))" }
        }
        let higherCaptor = ArgumentCaptor<ExternalTypedHigherOrderClosure>()
        let stub = try Stub<any ExternalDynamicTypedClosureService>()
        stub.when(returning: nullaryPlaceholder) {
            $0.nullary(nullaryCaptor.capture(using: nullaryPlaceholder))
        }.thenReturn(nullaryResult)
        stub.when(returning: higherPlaceholder) {
            $0.higherOrder(higherCaptor.capture(using: higherPlaceholder))
        }.thenReturn(higherResult)

        let value: any ExternalDynamicTypedClosureService = stub()
        let returnedNullary = value.nullary(nullaryInput)
        #expect(throws: nullaryFailure) { try returnedNullary() }
        let capturedNullary = try #require(nullaryCaptor.first)
        #expect(throws: nullaryFailure) { try capturedNullary() }

        let returnedHigher = value.higherOrder(higherInput)
        #expect(try returnedHigher(identity, 2)(21) == "returned-value-42")
        #expect(throws: ExternalDynamicClosureError.rejected(0)) {
            try returnedHigher(identity, 0)
        }
        let capturedHigher = try #require(higherCaptor.first)
        #expect(try capturedHigher(identity, 2)(21) == "input-value-42")
        #expect(throws: ExternalDynamicClosureError.rejected(0)) {
            try capturedHigher(identity, 0)
        }
    }

    @Test func dictionariesResultsAndEnumsPreserveClosurePayloads() throws {
        _ = RealExternalClosureCollectionService()
        let identity: ExternalContainerClosure = { "\($0)" }
        let dictionaryPlaceholder = ["identity": identity]
        let resultPlaceholder: ExternalClosureResult = .success(identity)
        let choicePlaceholder = ExternalClosureChoice.transform(identity)
        let stub = try Stub<any ExternalClosureCollectionService>()

        stub.when(returning: dictionaryPlaceholder) {
            $0.dictionary(any(using: dictionaryPlaceholder))
        }.then { (value: [String: ExternalContainerClosure]) in value }
        stub.when(returning: resultPlaceholder) {
            $0.result(any(using: resultPlaceholder))
        }.then { (value: ExternalClosureResult) in value }
        stub.when(returning: choicePlaceholder) {
            $0.choice(any(using: choicePlaceholder))
        }.then { (value: ExternalClosureChoice) in value }

        let value: any ExternalClosureCollectionService = stub()
        let transform: ExternalContainerClosure = { "\($0 * 2)!" }
        let dictionary = value.dictionary(["transform": transform])
        #expect(dictionary["transform"]?(21) == "42!")

        let result = value.result(.success(transform))
        switch result {
            case .success(let closure):
                #expect(closure(21) == "42!")
            case .failure(let error):
                Issue.record("Unexpected closure result error: \(error)")
        }

        let choice = value.choice(.transform(transform))
        switch choice {
            case .transform(let closure):
                #expect(closure(21) == "42!")
            case .none:
                Issue.record("Expected a closure payload.")
        }
    }

    @Test func resultPayloadsCrossHigherOrderClosures() throws {
        _ = RealExternalResultHigherOrderClosureService()
        let placeholder: ExternalResultHigherOrderClosure = { $0 }
        let configured: ExternalResultHigherOrderClosure = { result in
            result.map { transform in
                { value in "configured-\(transform(value))" }
            }
        }
        let input: ExternalResultHigherOrderClosure = { result in
            result.map { transform in
                { value in "input-\(transform(value * 2))" }
            }
        }
        let boxedPlaceholder: ExternalBoxHigherOrderClosure = { $0 }
        let boxedResult: ExternalBoxHigherOrderClosure = { box in
            ExternalGenericClosureBox(value: { value in
                "boxed-\(box.value(value))"
            })
        }
        let captor = ArgumentCaptor<ExternalResultHigherOrderClosure>()
        let boxedCaptor = ArgumentCaptor<ExternalBoxHigherOrderClosure>()
        let stub = try Stub<any ExternalResultHigherOrderClosureService>()
        stub.when(returning: placeholder) {
            $0.transform(captor.capture(using: placeholder))
        }.thenReturn(configured)
        stub.when(returning: boxedPlaceholder) {
            $0.boxed(boxedCaptor.capture(using: boxedPlaceholder))
        }.thenReturn(boxedResult)

        let base: ExternalContainerClosure = { "value-\($0)" }
        let returned = stub().transform(input)
        let returnedResult = returned(.success(base))
        switch returnedResult {
            case .success(let closure):
                #expect(closure(21) == "configured-value-21")
            case .failure(let error):
                Issue.record("Unexpected configured error: \(error)")
        }

        let captured = try #require(captor.first)
        let capturedResult = captured(.success(base))
        switch capturedResult {
            case .success(let closure):
                #expect(closure(21) == "input-value-42")
            case .failure(let error):
                Issue.record("Unexpected input error: \(error)")
        }

        let boxedInput: ExternalBoxHigherOrderClosure = { box in
            ExternalGenericClosureBox(value: { value in
                "input-\(box.value(value * 2))"
            })
        }
        let returnedBox = stub().boxed(boxedInput)(
            ExternalGenericClosureBox(value: base)
        )
        #expect(returnedBox.value(21) == "boxed-value-21")

        let capturedBoxed = try #require(boxedCaptor.first)
        let capturedBox = capturedBoxed(
            ExternalGenericClosureBox(value: base)
        )
        #expect(capturedBox.value(21) == "input-value-42")
    }
}
