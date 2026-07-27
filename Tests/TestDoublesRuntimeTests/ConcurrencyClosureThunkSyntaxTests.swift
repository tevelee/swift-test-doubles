import EchoRuntimeReflection
import Testing
@testable import TestDoublesRuntime
@testable import TestDoublesRuntimeMetadata

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
        #expect(FunctionSignatureMatcher.direct(parsed, matches: function))

        let ordinary = try #require(
            FunctionTypeInfo(
                reflecting: (@Sendable (String) -> String).self
            )
        )
        #expect(FunctionSignatureMatcher.direct(parsed, matches: ordinary) == false)
    }

    @Test func sendingResultCannotUseTheDynamicBridgeWhenRawFlagsOmitIt() throws {
        let function = try #require(
            FunctionTypeInfo(reflecting: SendingResultOnlySyntaxClosure.self)
        )

        #expect(runtimeFunctionHasSendingResult(function))
        #expect(hasOnlyDynamicallySupportedExtendedFlags(function) == false)
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

        #expect(FunctionSignatureMatcher.direct(parsed, matches: function))
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

        #expect(FunctionSignatureMatcher.direct(parsed, matches: function))
    }
}
