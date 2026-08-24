# ``TestDoubles``

Create small protocol-based test doubles without macros, generated conformers,
or per-stub compiler invocations.

## Overview

``Stub`` fabricates a protocol conformance and routes witness calls through a
fixed runtime trampoline. Configure behavior with `when`, `thenReturn`,
`thenThrow`, and `then`, then verify the interactions that matter to the test.

Use ``Spy`` to keep a real implementation as the default. Unmatched calls
forward to its target while matching `when` registrations override behavior;
both paths are recorded for verification.

Use ``Dummy`` when an API requires a value that the exercised code path must not
use. It fabricates protocol existentials, concrete placeholders, and functions;
protocol or function invocation fails closed with an actionable diagnostic.

Start with <doc:QuickStart> for the complete everyday API workflow, then use
<doc:GettingStarted> for properties, subscripts, initializers, dynamic `Self`,
and associated types. Use
<doc:AsyncBehaviors> to control when async requirements complete, for loading
states, timeouts, and cancellation, and <doc:InspectingInteractions> to read
recorded arguments, order calls across doubles, and reset a double between
cases. Use <doc:ConstructionGuide> when choosing a construction path,
<doc:StubContract> when checking the supported runtime boundary, and
<doc:ManualStubbing> when a hand-written conformer is a better fit. Use
<doc:ClosureClients> when dependencies are concrete structs whose operations
are stored closures. No construction path launches an external tool. The
generated existential owns its runtime resources and may outlive the ``Stub``
that created it.

Runtime stubs support synchronous, throwing, async, and async-throwing
requirements, inherited protocols, protocol compositions, direct property and
subscript setters, class-constrained protocols, `NSObject`-backed superclass
constraints, bounded primary-associated-type bindings across supported
inheritance and compositions, caller-supplied bindings for covariant associated
results, recording-result placeholders, direct and optional dynamic `Self`
results, initializer requirements, sequenced behaviors, delayed and
suspend-controlled async completion, immediate and eventual verification,
typed invocation access, cross-double ordered verification, invocation and
behavior clearing, and unverified- and unused-registration reporting.
Unsupported runtime shapes fail during construction when they can be detected.

Methods, static methods, initializers, properties, and subscripts may
automatically carry concrete Swift closures, C function pointers, and blocks
without requirement chunks or protocol annotations, including effects,
ownership modifiers, structural containers, nested closures, and actor
isolation. See
<doc:FunctionValues> for the exact automatic boundary and the explicit
`@convention(thin)` fallback.

## Topics

### Start Here

- <doc:QuickStart>
- <doc:GettingStarted>
- <doc:AsyncBehaviors>
- <doc:InspectingInteractions>
- <doc:ForwardingSpies>
- <doc:StubContract>
- <doc:ManualStubbing>
- <doc:ClosureClients>

### Runtime Stub API

- ``TestDouble``
- ``Stub``
- ``StubConstructionStrategy``
- ``Spy``
- ``CallPattern``
- ``ConfiguredCall``
- ``CallInteractions``
- ``StubBehaviorChain``
- ``StubBehaviorQueue``
- ``StubSuspension``
- ``Stub/Invocation``
- ``InteractionHistory``
- ``InteractionTimeline``
- ``StubClock``
- ``ManualStubClock``
- <doc:FunctionValues>

### Inspecting and Ordering Interactions

- <doc:InspectingInteractions>
- ``InvocationOrder``
- ``Match/Placeholders``

### Recording and Replaying Interactions

- <doc:RecordAndReplay>
- ``RecordingSession``
- ``InteractionFixture``

### Reusable Setup

- <doc:ReusableScenarios>
- ``StubScenario``
- ``ManualStubScenario``
- ``AsyncStubScenario``
- ``AsyncManualStubScenario``

### Dummy API

- ``Dummy``
- <doc:DummyTestDoubles>

### Construction and Signatures

- ``Stub/Requirement``
- ``Stub/Requirement/Value``
- ``Stub/ProtocolRequirements``
- ``Stub/AssociatedTypeBinding``
- ``Stub/GetterEffect``
- ``Stub/ProtocolGetterEffects``
- <doc:ConstructionGuide>
- <doc:BoundAssociatedTypes>

### Initializers and Dynamic Self

- ``StubInitializerBuilder``
- ``StubFailableInitializerBuilder``
- ``StubSelfResultBuilder``
- ``StubOptionalSelfResultBuilder``

### Manual Stubbing

- ``ManualStub``
- ``ManualStubConformer``
- ``ManualRequirementRoute``
- ``ManualThrowingRequirementRoute``

### Closure-Based Dependencies

- <doc:ClosureClients>
- ``ClientStub``
- ``ClientSpy``
- ``ClientDoublePreset``
- ``ClientStubEndpoints``

### Matching and Capture

- ``Match/any()``
- ``Match/any(using:)``
- ``Match/equal(_:)``
- ``Match/notEqual(_:)``
- ``Match/identical(to:)``
- ``Match/matching(description:where:)``
- ``Match/matching(using:description:where:)``
- ``CustomMatcher``
- ``Match/custom(_:)``
- ``Match/custom(using:_:)``
- ``ArgumentCaptor``
- ``ClosureDouble``
- ``ClosureCallPattern``
- ``VoidClosureDouble``
- ``ThrowingClosureDouble``
- ``ThrowingClosureCallPattern``
- ``AsyncClosureDouble``
- ``AsyncClosureCallPattern``
- ``AsyncThrowingClosureDouble``
- ``AsyncThrowingClosureCallPattern``
- ``ClosureSpy``
- ``ThrowingClosureSpy``
- ``AsyncClosureSpy``
- ``AsyncThrowingClosureSpy``
- ``SendableClosureDouble``
- ``SendableThrowingClosureDouble``
- ``SendableAsyncClosureDouble``
- ``SendableAsyncThrowingClosureDouble``
- ``TypedThrowingClosureDouble``
- ``AsyncTypedThrowingClosureDouble``
- ``TypedThrowingClosureSpy``
- ``AsyncTypedThrowingClosureSpy``
- ``InoutClosureDouble``
- ``InoutClosureCallPattern``
- ``InoutClosureBehaviorChain``
- ``InoutClosureOutcome``
- ``InoutClosureSpy``
- ``ClosureArgumentHistory``
- ``VariadicClosureDouble``
- ``VariadicThrowingClosureDouble``
- ``VariadicAsyncClosureDouble``
- ``VariadicAsyncThrowingClosureDouble``
- ``VariadicTypedThrowingClosureDouble``
- ``VariadicAsyncTypedThrowingClosureDouble``
- ``ParameterPackClosureDouble``
- ``ParameterPackThrowingClosureDouble``
- ``ParameterPackAsyncClosureDouble``
- ``ParameterPackAsyncThrowingClosureDouble``
- ``ParameterPackTypedThrowingClosureDouble``
- ``ParameterPackAsyncTypedThrowingClosureDouble``
- ``NonescapingCallbackRecorder``
- ``MainActorClosureDouble``
- ``MainActorThrowingClosureDouble``
- ``MainActorAsyncClosureDouble``
- ``MainActorAsyncThrowingClosureDouble``
- ``MainActorTypedThrowingClosureDouble``
- ``MainActorAsyncTypedThrowingClosureDouble``
- ``CallbackCapture``
- ``AsyncStreamController``
- ``AsyncThrowingStreamController``
- ``AsyncStreamControllerTermination``

### Value and Optional Matchers

- ``Match/greaterThan(_:)``
- ``Match/atLeast(_:)``
- ``Match/lessThan(_:)``
- ``Match/atMost(_:)``
- ``Match/inRange(_:)-(Range<Bound>)``
- ``Match/inRange(_:)-(ClosedRange<Bound>)``
- ``Match/isNil()``
- ``Match/notNil()``
- ``Match/some(_:)``

### Collection Matchers

- ``Match/isEmpty()``
- ``Match/nonEmpty()``
- ``Match/hasCount(_:)``
- ``Match/hasCount(matching:)``
- ``Match/contains(_:)``
- ``Match/contains(where:)``
- ``Match/containsAll(_:)``
- ``Match/startsWith(_:)``
- ``Match/endsWith(_:)``

### String Matchers

- ``Match/hasPrefix(_:)``
- ``Match/hasSuffix(_:)``
- ``Match/containsSubstring(_:)``
- ``Match/equalsIgnoringCase(_:)``
- ``Match/matchesRegex(_:)-(String)``
- ``Match/matchesRegex(_:)-(Regex<Output>)``

### Composing Matchers

- ``Match/not(_:)``
- ``Match/allOf(_:_:)``
- ``Match/allOf(_:_:_:)``
- ``Match/allOf(_:_:_:_:)``
- ``Match/anyOf(_:_:)``
- ``Match/anyOf(_:_:_:)``
- ``Match/anyOf(_:_:_:_:)``
- ``Match/oneOf(_:)``

### Diagnostics and Runtime Internals

- ``TestDoubleIssue``
- ``StubError``
- <doc:HowRuntimeStubsWork>
- <doc:ClosureReabstractionInternals>
- <doc:TrampolineArchitecture>
