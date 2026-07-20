import Foundation
import Testing
import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol UnstubbedBehaviorProbe {
    func greet(name: String) -> String
    func total(of values: [Int]) throws -> Int
}

struct RealUnstubbedBehaviorProbe: UnstubbedBehaviorProbe {
    func greet(name: String) -> String { name }
    func total(of values: [Int]) throws -> Int { values.count }
}

private protocol UnstubbedManualProbe {
    func load() -> String
}

private protocol MissingImplementationProbe {
    func load() -> String
}

protocol UnfinishedVoidConfigurationProbe {
    func reset()
}

struct RealUnfinishedVoidConfigurationProbe: UnfinishedVoidConfigurationProbe {
    func reset() {}
}

private struct UnstubbedManualProbeStub: UnstubbedManualProbe, StubConformer {
    let stub: ManualStub<Self>
    func load() -> String { stub.load() }
}

private struct ManualLoadError: Error {}
private struct UnexpectedTypedError: Error {}

/// An unconfigured requirement is a test bug, so invoking one halts the test
/// process with an actionable diagnostic instead of inventing behavior.
#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    enum UnstubbedExitScenario: CaseIterable, Sendable {
        case unstubbedRequirement
        case missingConformanceMetadata
        case unmatchedArguments
        case throwingRequirement
        case unfinishedVoidConfiguration
        case emptyRecordingClosure
        case multipleRecordedRequirements
        case nonthrowingThenThrow
        case mismatchedTypedError
        case throwingManualHandler
        case explicitFatalError
        case timesBelowOne
        case appendingAfterUnbounded
        case timesIntShorthandBelowOne
    }

    @Suite struct UnstubbedBehaviorExitTests {
        @Test(.serialized, arguments: UnstubbedExitScenario.allCases)
        func processExitDiagnostics(_ scenario: UnstubbedExitScenario) async throws {
            switch scenario {
                case .unstubbedRequirement:
                    try await invokingAnUnstubbedRequirementHaltsWithASuggestedStub()
                case .missingConformanceMetadata:
                    try await factoryFailureExplainsHowToSupplyMissingConformanceMetadata()
                case .unmatchedArguments:
                    try await invokingWithUnmatchedArgumentsHaltsListingRegisteredStubs()
                case .throwingRequirement:
                    try await throwingRequirementsHaltRatherThanInventAnError()
                case .unfinishedVoidConfiguration:
                    try await unfinishedVoidConfigurationDoesNotInstallBehavior()
                case .emptyRecordingClosure:
                    try await recordingClosuresMustInvokeARequirement()
                case .multipleRecordedRequirements:
                    try await singleInvocationRecordingClosuresRejectMultipleRequirements()
                case .nonthrowingThenThrow:
                    try await thenThrowRejectsNonthrowingRequirementsAtConfiguration()
                case .mismatchedTypedError:
                    try await thenThrowRejectsMismatchedTypedErrorsAtConfiguration()
                case .throwingManualHandler:
                    try await manualNonthrowingRouteHaltsWhenAHandlerThrows()
                case .explicitFatalError:
                    try await thenFatalErrorHaltsWithTheConfiguredMessage()
                case .timesBelowOne:
                    try await timesBelowOneHaltsAtConfiguration()
                case .appendingAfterUnbounded:
                    try await appendingAfterUnboundedHaltsAtConfiguration()
                case .timesIntShorthandBelowOne:
                    try await timesIntShorthandBelowOneHaltsAtConfiguration()
            }
        }

        private func invokingAnUnstubbedRequirementHaltsWithASuggestedStub() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                _ = stub().greet(name: "eve")
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("No stub configured for greet(name:)"))
            #expect(diagnostic.contains("arg0: \"eve\""))
            #expect(
                diagnostic.contains("stub.when { $0.greet(name: equal(\"eve\")) }.thenReturn(...)")
            )
        }

        private func factoryFailureExplainsHowToSupplyMissingConformanceMetadata() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let _: any MissingImplementationProbe = makeStub { _ in }
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(
                diagnostic.contains(
                    "neither a linked conformer nor resilient requirement symbols"
                )
            )
            #expect(diagnostic.contains("1. Linked conformer:"))
            #expect(diagnostic.contains("2. Library evolution:"))
            #expect(diagnostic.contains("no conformer is needed"))
            #expect(diagnostic.contains("3. Neither source available:"))
            #expect(diagnostic.contains("`Requirement` factories using `signatureOf:`"))
            #expect(diagnostic.contains("source-less factories"))
        }

        private func invokingWithUnmatchedArgumentsHaltsListingRegisteredStubs() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { $0.greet(name: equal("alice")) }.thenReturn("hi")
                _ = stub().greet(name: "bob")
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("No matching stub for greet(name:)"))
            #expect(diagnostic.contains("greet(name:)(equal(alice))"))
        }

        private func throwingRequirementsHaltRatherThanInventAnError() async throws {
            // A throwing requirement does not turn "unstubbed" into a thrown
            // error: only configured behavior may produce values or errors.
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                _ = try stub().total(of: [1, 2])
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("No stub configured for total(of:)"))
        }

        private func unfinishedVoidConfigurationDoesNotInstallBehavior() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = RealUnfinishedVoidConfigurationProbe()
                let stub = try Stub<any UnfinishedVoidConfigurationProbe>()
                _ = stub.when { $0.reset() }
                stub().reset()
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("No stub configured for reset()"))
            #expect(diagnostic.contains("stub.when { $0.reset() }.thenDoNothing()"))
        }

        private func recordingClosuresMustInvokeARequirement() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { (_: any UnstubbedBehaviorProbe) -> String in "no invocation" }
                    .thenReturn("unreachable")
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("recording closure did not invoke a protocol requirement"))
            #expect(diagnostic.contains("Call exactly one requirement inside `when` or `verify`"))
        }

        private func singleInvocationRecordingClosuresRejectMultipleRequirements() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { probe in
                    _ = probe.greet(name: "first")
                    return probe.greet(name: "second")
                }.thenReturn("unreachable")
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("recording closure invoked 2 protocol requirements"))
            #expect(diagnostic.contains("Split them into separate operations"))
            #expect(diagnostic.contains("use `verifyInOrder`"))
        }

        private func thenThrowRejectsNonthrowingRequirementsAtConfiguration() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { $0.greet(name: any()) }.thenThrow(ManualLoadError())
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("thenThrow requires a throwing requirement"))
        }

        private func thenThrowRejectsMismatchedTypedErrorsAtConfiguration() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = RealTypedThrowsRequirementProbe()
                let stub = try Stub<any TypedThrowsRequirementProbe>()
                stub.when { try $0.load() }.thenThrow(UnexpectedTypedError())
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("Typed error must be"))
            #expect(diagnostic.contains("UnexpectedTypedError"))
        }

        private func manualNonthrowingRouteHaltsWhenAHandlerThrows() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = ManualStub<UnstubbedManualProbeStub>()
                stub.when { $0.load() }.then { () throws -> String in
                    throw ManualLoadError()
                }
                _ = stub().load()
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("A nonthrowing stub handler for 'load()' threw"))
            #expect(diagnostic.contains("Forward this requirement through `stub.throwing`"))
        }

        /// An overrun on an exhausted chain is a test bug the same way an
        /// unstubbed call is: `thenFatalError` opts a specific matcher into
        /// halting instead of letting the preceding behavior repeat.
        private func thenFatalErrorHaltsWithTheConfiguredMessage() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { $0.greet(name: any()) }
                    .thenFatalError("greet should not be called more than expected")
                _ = stub().greet(name: "eve")
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(
                diagnostic.contains(
                    "Explicit stub failure: greet should not be called more than expected"
                )
            )
            #expect(diagnostic.contains("greet(name:)"))
            #expect(diagnostic.contains("arg0: \"eve\""))
        }

        private func timesBelowOneHaltsAtConfiguration() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { $0.greet(name: any()) }.thenReturn("hi", times: 0 ... 3)
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("times: must start at 1"))
        }

        /// The `times: Int` shorthand builds `1...times` internally; a count
        /// below 1 must still surface the library's own diagnostic instead of
        /// crashing inside `ClosedRange`'s own precondition first.
        ///
        /// `StubBuilder` and `StubBehaviorChain` each implement this
        /// overload independently, so the first call (a valid count, on
        /// `StubBuilder`) chains into the second (the invalid one, on
        /// `StubBehaviorChain`) to reach both from one exit test rather than
        /// spawning a subprocess per type for what's the same guard.
        private func timesIntShorthandBelowOneHaltsAtConfiguration() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                stub.when { $0.greet(name: any()) }
                    .thenReturn("hi", times: 2)
                    .thenReturn("bye", times: 0)
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("times: must be at least 1"))
        }

        /// A fluent chain can't type-check an append after an unbounded
        /// entry — every unbounded-producing overload returns `Void`. A
        /// captured, explicitly type-annotated handle still reaches the
        /// append at runtime, though: the annotation forces the bounded
        /// call that creates `chain` to resolve to its disfavored
        /// chain-returning overload, and nothing about `chain`'s type
        /// changes when a later, separate statement calls the bare
        /// `thenReturn` that seals it with an unbounded entry. Same
        /// underlying mistake as a single fluent expression, same halt.
        private func appendingAfterUnboundedHaltsAtConfiguration() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnstubbedBehaviorProbe>()
                let chain: StubBehaviorChain<String> = stub.when { $0.greet(name: any()) }
                    .thenReturn("hi", times: 2)
                chain.thenReturn("bye")
                chain.thenReturn("late", times: 1 ... 1)
            }

            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(
                diagnostic.contains(
                    "Cannot append another behavior after an unbounded one"
                )
            )
        }
    }
#endif
