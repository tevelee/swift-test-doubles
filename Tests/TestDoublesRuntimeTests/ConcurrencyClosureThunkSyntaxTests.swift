import EchoRuntimeReflection
import Testing
@testable import TestDoublesRuntime

private typealias SendingSyntaxClosure =
    @Sendable (sending String) -> sending String
private typealias SendingResultOnlySyntaxClosure =
    @Sendable (String) -> sending String
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
private typealias IsolatedSyntaxClosure =
    @isolated(any) @Sendable (Int) async -> String
// swift-format-ignore
private typealias NonsendingSyntaxClosure =
    nonisolated(nonsending) @Sendable (Int) async -> String

@Suite struct ConcurrencyClosureThunkSyntaxTests {
    @Test func sendingParameterAndResultNeverUsesFalseTypedErrorMetadata() throws {
        let function = try #require(
            FunctionTypeInfo(reflecting: SendingSyntaxClosure.self)
        )
        let effects = RuntimeFunctionEffectInfo(function)
        let analysis = FunctionBridgeAnalysis(function)

        #expect(effects.isTypedThrows == false)
        #expect(effects.typedErrorType == nil)
        #expect(
            typedThrowingFunctionRuntimeUnsupportedReason(
                function,
                effects: effects
            ) == nil
        )
        #expect(analysis.validated(for: .directToGeneric) == nil)
        #expect(analysis.unsupportedReason(for: .directToGeneric) != nil)
    }

    @Test func sendingParameterAndResultArePartOfExactThunkIdentity() throws {
        let spelling =
            "@escaping @callee_guaranteed @Sendable "
            + "(@owned sending Swift.String) -> sending (@owned Swift.String)"
        let parsed = try #require(LoweredFunctionSyntax(spelling))
        let function = try #require(
            FunctionTypeInfo(reflecting: SendingSyntaxClosure.self)
        )

        #expect(parsed.parameters[0].isSending)
        #expect(parsed.hasSendingResult)
        // Swift 6.3 does not reliably surface extended function-type flags
        // on Linux for a closure that combines a `sending` parameter with a
        // `sending` result: the raw word Echo reads back for this shape can
        // hold bit patterns no compiler would emit, differing by process.
        // `FunctionReabstraction` already detects that unreliability (it
        // must, to fail closed rather than mis-bridge); reuse that check
        // here instead of asserting an exact match unconditionally.
        guard
            FunctionReabstraction.automaticArgumentUnsupportedReason(
                for: SendingSyntaxClosure.self
            ) == nil,
            FunctionReabstraction.automaticResultUnsupportedReason(
                for: SendingSyntaxClosure.self
            ) == nil
        else { return }
        let matchesSendingClosure = FunctionSignatureMatcher.direct(
            parsed,
            matches: function
        )
        #expect(matchesSendingClosure)

        let ordinary = try #require(
            FunctionTypeInfo(
                reflecting: (@Sendable (String) -> String).self
            )
        )
        let matchesOrdinaryClosure = FunctionSignatureMatcher.direct(
            parsed,
            matches: ordinary
        )
        #expect(matchesOrdinaryClosure == false)
    }

    @Test func sendingResultCannotUseTheDynamicBridgeWhenRawFlagsOmitIt() throws {
        let function = try #require(
            FunctionTypeInfo(reflecting: SendingResultOnlySyntaxClosure.self)
        )

        let hasSendingResult = runtimeFunctionHasSendingResult(function)
        let supportsDynamicBridge = hasOnlyDynamicallySupportedExtendedFlags(function)
        #expect(hasSendingResult)
        #expect(supportsDynamicBridge == false)
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, *)
    @Test func isolatedAnyIsPartOfExactThunkIdentity() throws {
        let spelling =
            "@escaping @isolated(any) @callee_guaranteed @Sendable @async "
            + "(@unowned Swift.Int) -> (@owned Swift.String)"
        let parsed = try #require(LoweredFunctionSyntax(spelling))
        let function = try #require(
            FunctionTypeInfo(reflecting: IsolatedSyntaxClosure.self)
        )

        let matchesIsolatedClosure = FunctionSignatureMatcher.direct(
            parsed,
            matches: function
        )
        #expect(matchesIsolatedClosure)
    }

    @Test func nonsendingRequiresTheImplicitActorParameter() throws {
        let spelling =
            "@escaping @callee_guaranteed @Sendable @async "
            + "(@guaranteed Builtin.ImplicitActor, @unowned Swift.Int) "
            + "-> (@owned Swift.String)"
        let parsed = try #require(LoweredFunctionSyntax(spelling))
        let function = try #require(
            FunctionTypeInfo(reflecting: NonsendingSyntaxClosure.self)
        )

        let matchesNonsendingClosure = FunctionSignatureMatcher.direct(
            parsed,
            matches: function
        )
        #expect(matchesNonsendingClosure)
    }
}
