import TestDoubles
import TestDoublesFixtures
import Testing

private final class ClosureLifetimeToken: @unchecked Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

private final class WeakClosureLifetimeTokenBox: @unchecked Sendable {
    weak var value: ClosureLifetimeToken?
}

private func makeManagedClosure(
    retainedBy reference: WeakClosureLifetimeTokenBox
) -> ExternalManagedClosure {
    let token = ClosureLifetimeToken("")
    reference.value = token
    return { [token] value in token.value + value + "-" }
}

private func invokeManagedClosure(
    on stub: Stub<any ExternalAdvancedClosureService>?,
    with argument: ExternalManagedClosure?
) throws -> ExternalManagedClosure {
    let stub = try #require(stub)
    let argument = try #require(argument)
    return stub().managed(argument)
}

private func configureManagedClosure(
    on stub: Stub<any ExternalAdvancedClosureService>?,
    identity: @escaping ExternalManagedClosure,
    returnedToken: WeakClosureLifetimeTokenBox
) throws {
    let stub = try #require(stub)
    stub.when(returning: identity) {
        $0.managed(any(using: identity))
    }.then { (closure: ExternalManagedClosure) in
        let token = ClosureLifetimeToken(closure("forty"))
        returnedToken.value = token
        return { suffix in token.value + suffix }
    }
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
private func inheritIsolation(
    @_inheritActorContext _ operation: @escaping ExternalIsolatedClosure
) -> ExternalIsolatedClosure {
    operation
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
private actor ClosureIsolationActor {
    private var invocationCount = 0

    func makeResult() -> ExternalIsolatedClosure {
        inheritIsolation { [self] value in
            invocationCount += 1
            return "\(value * 3)?"
        }
    }
}

@Suite struct AdvancedRuntimeClosureTests {
    @Test func managedClosuresPreserveCapturedValuesAndLifetimes() throws {
        _ = RealExternalAdvancedClosureService()
        let identity: ExternalManagedClosure = { $0 }
        let returnedToken = WeakClosureLifetimeTokenBox()
        var stub: Stub<any ExternalAdvancedClosureService>? =
            try Stub<any ExternalAdvancedClosureService>()
        try configureManagedClosure(
            on: stub,
            identity: identity,
            returnedToken: returnedToken
        )

        let argumentToken = WeakClosureLifetimeTokenBox()
        var argument: ExternalManagedClosure? = makeManagedClosure(retainedBy: argumentToken)
        var transformed: ExternalManagedClosure? = try invokeManagedClosure(
            on: stub,
            with: argument
        )
        argument = nil

        #expect(argumentToken.value != nil)
        #expect(returnedToken.value != nil)
        #expect(transformed?("two") == "forty-two")

        stub = nil
        #expect(argumentToken.value == nil)
        #expect(returnedToken.value != nil)

        transformed = nil
        #expect(returnedToken.value == nil)
    }

    @Test func throwingClosureValuesPreserveEffects() throws {
        _ = RealExternalAdvancedClosureService()
        let identity: ExternalThrowingClosure = { "\($0)" }
        let stub = try Stub<any ExternalAdvancedClosureService>()
        stub.when(returning: identity) {
            $0.throwing(any(using: identity))
        }.then { (closure: ExternalThrowingClosure) in
            let captured = Result { try closure(21) }
            return { _ in try captured.get() + "!" }
        }

        let transformed = stub().throwing { "\($0 * 2)" }
        #expect(try transformed(0) == "42!")
    }

    @Test func asyncClosureValuesPreserveEffects() async throws {
        _ = RealExternalAdvancedClosureService()
        let identity: ExternalAsyncClosure = { "\($0)" }
        let stub = try Stub<any ExternalAdvancedClosureService>()
        stub.when(returning: identity) {
            $0.asynchronous(any(using: identity))
        }.then { (_: ExternalAsyncClosure) in
            { @Sendable value in
                await Task.yield()
                return "\(value * 2)!"
            }
        }

        let transformed = stub().asynchronous { value in
            await Task.yield()
            return "\(value)"
        }
        #expect(await transformed(21) == "42!")
    }

    @Test func asyncThrowingClosureValuesPreserveBothEffects() async throws {
        _ = RealExternalAdvancedClosureService()
        let identity: ExternalAsyncThrowingClosure = { $0.count }
        let stub = try Stub<any ExternalAdvancedClosureService>()
        stub.when(returning: identity) {
            $0.asynchronousThrowing(any(using: identity))
        }.then { (_: ExternalAsyncThrowingClosure) in
            { @Sendable value in
                await Task.yield()
                guard value != "fail" else { throw ExternalClosureError.failed }
                return value.count * 2
            }
        }

        let transformed = stub().asynchronousThrowing { value in
            await Task.yield()
            guard value != "fail" else { throw ExternalClosureError.failed }
            return value.count
        }
        #expect(try await transformed("twenty-one") == 20)
        await #expect(throws: ExternalClosureError.failed) {
            try await transformed("fail")
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func asyncTypedThrowingClosureValuesPreserveTypedErrors() async throws {
        _ = RealExternalExtendedClosureService()
        let identity: ExternalAsyncTypedThrowingClosure = { "\($0)" }
        let stub = try Stub<any ExternalExtendedClosureService>()
        stub.when(returning: identity) {
            $0.asyncTypedThrowing(any(using: identity))
        }.then { (_: ExternalAsyncTypedThrowingClosure) in
            { @Sendable value async throws(ExternalClosureError) in
                await Task.yield()
                guard value != 0 else { throw ExternalClosureError.failed }
                return "\(value * 2)!"
            }
        }

        let input: ExternalAsyncTypedThrowingClosure = {
            value async throws(ExternalClosureError) in
            await Task.yield()
            guard value != 0 else { throw ExternalClosureError.failed }
            return "\(value)"
        }
        let transformed = stub().asyncTypedThrowing(input)
        #expect(try await transformed(21) == "42!")
        await #expect(throws: ExternalClosureError.failed) {
            try await transformed(0)
        }
    }

    @Test func asyncClosureArgumentsSuspendInsideAsyncHandlers() async throws {
        _ = RealExternalAdvancedClosureService()
        let stringIdentity: ExternalAsyncClosure = { "\($0)" }
        let throwingIdentity: ExternalAsyncThrowingClosure = { $0.count }
        let stub = try Stub<any ExternalAdvancedClosureService>()

        await stub.when(returning: "") {
            await $0.invokeAsyncClosure(
                any(using: stringIdentity),
                value: any()
            )
        }.thenEscaping { (closure: ExternalAsyncClosure, value: Int) async in
            await Task.yield()
            return await closure(value) + "!"
        }
        await stub.when(returning: 0) {
            try await $0.invokeAsyncThrowingClosure(
                any(using: throwingIdentity),
                value: any()
            )
        }.thenEscaping {
            (closure: ExternalAsyncThrowingClosure, value: String) async throws in
            await Task.yield()
            return try await closure(value) * 2
        }

        let stringResult = await stub().invokeAsyncClosure(
            { value in
                await Task.yield()
                return "\(value * 2)"
            },
            value: 21
        )
        #expect(stringResult == "42!")

        let throwingResult = try await stub().invokeAsyncThrowingClosure(
            { value in
                await Task.yield()
                guard value != "fail" else {
                    throw ExternalClosureError.failed
                }
                return value.count
            },
            value: "twenty-one"
        )
        #expect(throwingResult == 20)
        await #expect(throws: ExternalClosureError.failed) {
            try await stub().invokeAsyncThrowingClosure(
                { _ in throw ExternalClosureError.failed },
                value: "fail"
            )
        }
    }

    @Test func asyncMixedClosuresPreserveRegistersAndIndirectResults() async throws {
        _ = RealExternalAdvancedClosureService()
        let placeholder: ExternalAsyncMixedClosure = {
            value, _, enabled, label in
            ExternalNullaryAggregate(
                label: label,
                count: value,
                enabled: enabled
            )
        }
        let stub = try Stub<any ExternalAdvancedClosureService>()

        stub.when(returning: placeholder) {
            $0.asynchronousMixed(any(using: placeholder))
        }.then { (_: ExternalAsyncMixedClosure) in
            { @Sendable value, floating, enabled, label in
                await Task.yield()
                return ExternalNullaryAggregate(
                    label: "\(label)-\(floating)",
                    count: value * 2,
                    enabled: enabled
                )
            }
        }
        let returned = stub().asynchronousMixed(placeholder)
        #expect(
            try await returned(21, 1.5, true, "mixed")
                == ExternalNullaryAggregate(
                    label: "mixed-1.5",
                    count: 42,
                    enabled: true
                )
        )
    }

    @Test func ownershipQualifiedClosureValuesPreserveCallingConventions() throws {
        _ = RealExternalAdvancedClosureService()
        let inoutIdentity: ExternalInoutClosure = { $0 += 1 }
        let inoutResult: ExternalInoutClosure = { $0 *= 2 }
        let consumingIdentity: ExternalConsumingClosure = { $0 }
        let consumingResult: ExternalConsumingClosure = { $0.uppercased() }
        let borrowingIdentity: ExternalBorrowingClosure = { $0 }
        let borrowingResult: ExternalBorrowingClosure = { $0.uppercased() }
        let stub = try Stub<any ExternalAdvancedClosureService>()

        stub.when(returning: inoutIdentity) {
            $0.inoutValue(any(using: inoutIdentity))
        }.then { (_: ExternalInoutClosure) in inoutResult }
        stub.when(returning: consumingIdentity) {
            $0.consuming(any(using: consumingIdentity))
        }.then { (_: ExternalConsumingClosure) in consumingResult }
        stub.when(returning: borrowingIdentity) {
            $0.borrowing(any(using: borrowingIdentity))
        }.then { (_: ExternalBorrowingClosure) in borrowingResult }

        let inoutClosure = stub().inoutValue(inoutIdentity)
        var value = 21
        inoutClosure(&value)
        #expect(value == 42)
        #expect(stub().consuming(consumingIdentity)("owned") == "OWNED")
        #expect(stub().borrowing(borrowingIdentity)("shared") == "SHARED")
    }

    @Test func variadicAutoclosureAndNestedFunctionValuesDispatch() throws {
        _ = RealExternalAdvancedClosureService()
        let variadicIdentity: ExternalVariadicClosure = { $0.reduce(0, +) }
        let variadicResult: ExternalVariadicClosure = { $0.reduce(1, *) }
        let autoclosureIdentity: ExternalAutoclosureClosure = { $0() }
        let autoclosureResult: ExternalAutoclosureClosure = { $0() * 2 }
        let nestedIdentity: ExternalNestedClosure = { $0 }
        let stub = try Stub<any ExternalAdvancedClosureService>()

        stub.when(returning: variadicIdentity) {
            $0.variadic(any(using: variadicIdentity))
        }.then { (_: ExternalVariadicClosure) in variadicResult }
        stub.when(returning: autoclosureIdentity) {
            $0.autoclosure(any(using: autoclosureIdentity))
        }.then { (_: ExternalAutoclosureClosure) in autoclosureResult }
        stub.when(returning: nestedIdentity) {
            $0.nested(any(using: nestedIdentity))
        }.then { (closure: ExternalNestedClosure) in
            let inner = closure { $0 * 2 }
            let captured = inner(20) + 2
            return { _ in { _ in captured } }
        }

        #expect(stub().variadic(variadicIdentity)(2, 3, 7) == 42)
        #expect(stub().autoclosure(autoclosureIdentity)(21) == 42)
        let nested = stub().nested(nestedIdentity)
        #expect(nested { $0 }(0) == 42)
    }

    @Test func closureValuesCrossAsyncAndThrowingRequirements() async throws {
        _ = RealExternalAdvancedClosureService()
        let managedIdentity: ExternalManagedClosure = { $0 }
        let throwingIdentity: ExternalThrowingClosure = { "\($0)" }
        let stub = try Stub<any ExternalAdvancedClosureService>()

        await stub.when(returning: managedIdentity) {
            await $0.asynchronousRequirement(any(using: managedIdentity))
        }.thenEscaping { (closure: ExternalManagedClosure) async in
            let captured = closure("forty-")
            return { captured + $0 }
        }
        await stub.when(returning: throwingIdentity) {
            try await $0.asyncThrowingRequirement(any(using: throwingIdentity))
        }.thenEscaping { (closure: ExternalThrowingClosure) async throws in
            let captured = try closure(21)
            return { _ in captured + "!" }
        }

        let managed = await stub().asynchronousRequirement { $0 }
        #expect(managed("two") == "forty-two")
        let throwing = try await stub().asyncThrowingRequirement { "\($0 * 2)" }
        #expect(try throwing(0) == "42!")
    }

    @Test func moveOnlyInnerValuesPreserveOwnership() throws {
        _ = RealExternalMoveOnlyClosureService()
        let identity: ExternalMoveOnlyClosure = {
            (value: consuming ExternalMoveOnlyValue) in value.value
        }
        let result: ExternalMoveOnlyClosure = {
            (value: consuming ExternalMoveOnlyValue) in value.value * 2
        }
        let stub = try Stub<any ExternalMoveOnlyClosureService>()
        stub.when(returning: identity) {
            $0.transform(any(using: identity))
        }.then { (_: ExternalMoveOnlyClosure) in result }

        let transformed = stub().transform(identity)
        #expect(transformed(ExternalMoveOnlyValue(21)) == 42)
    }

    @Test func nonescapingClosureArgumentsFailDuringConstruction() {
        _ = RealExternalNonescapingClosureService()
        #expect(throws: StubError.self) {
            try Stub<any ExternalNonescapingClosureService>()
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func typedThrowingClosureValuesPreserveTypedErrors() throws {
        _ = RealExternalExtendedClosureService()
        let identity: ExternalTypedThrowingClosure = { "\($0)" }
        let result: ExternalTypedThrowingClosure = {
            value throws(ExternalClosureError) in
            guard value != 0 else { throw ExternalClosureError.failed }
            return "\(value * 2)!"
        }
        let stub = try Stub<any ExternalExtendedClosureService>()
        stub.when(returning: identity) {
            $0.typedThrowing(any(using: identity))
        }.then { (_: ExternalTypedThrowingClosure) in result }

        let transformed = stub().typedThrowing(identity)
        #expect(try transformed(21) == "42!")
        #expect(throws: ExternalClosureError.failed) {
            try transformed(0)
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @MainActor
    @Test func globalActorClosureValuesPreserveIsolation() throws {
        _ = RealExternalExtendedClosureService()
        let identity: ExternalMainActorClosure = { "\($0)" }
        let result: ExternalMainActorClosure = { "\($0 * 2)!" }
        let stub = try Stub<any ExternalExtendedClosureService>()
        stub.when(returning: identity) {
            $0.mainActor(any(using: identity))
        }.then { (_: ExternalMainActorClosure) in result }

        let transformed = stub().mainActor(identity)
        #expect(transformed(21) == "42!")
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func isolatedAnyClosureValuesPreserveDynamicActorIsolation() async throws {
        _ = RealExternalExtendedClosureService()
        let identity: ExternalIsolatedClosure = { "\($0)" }
        let actor = ClosureIsolationActor()
        let result = await actor.makeResult()
        #expect(result.isolation === actor)
        let stub = try Stub<any ExternalExtendedClosureService>()
        stub.when(returning: identity) {
            $0.isolated(any(using: identity))
        }.then { (_: ExternalIsolatedClosure) in result }

        let transformed = stub().isolated(identity)
        #expect(transformed.isolation === actor)
        #expect(await transformed(14) == "42?")
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func transferAndNonsendingClosureFlagsRoundTrip() async throws {
        _ = RealExternalExtendedClosureService()
        let sendingIdentity: ExternalSendingClosure = { $0 }
        let sendingResult: ExternalSendingClosure = { $0.uppercased() }
        let nonsendingIdentity: ExternalNonsendingClosure = { "\($0)" }
        let nonsendingResult: ExternalNonsendingClosure = { "\($0 * 2)!" }
        let stub = try Stub<any ExternalExtendedClosureService>()

        stub.when(returning: sendingIdentity) {
            $0.sending(any(using: sendingIdentity))
        }.then { (_: ExternalSendingClosure) in sendingResult }
        stub.when(returning: nonsendingIdentity) {
            $0.nonsending(any(using: nonsendingIdentity))
        }.then { (_: ExternalNonsendingClosure) in nonsendingResult }

        #expect(stub().sending(sendingIdentity)("answer") == "ANSWER")
        #expect(await stub().nonsending(nonsendingIdentity)(21) == "42!")
    }
}
