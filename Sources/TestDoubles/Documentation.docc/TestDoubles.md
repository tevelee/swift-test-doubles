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

Use ``Dummy`` when an API requires a protocol value that the exercised code path
must not use. A dummy has no behavior or recorder, and every invocation fails
closed with an actionable diagnostic.

Start with <doc:GettingStarted> for task-oriented examples. Use
<doc:AsyncBehaviors> to control when async requirements complete, for loading
states, timeouts, and cancellation, and <doc:InspectingInteractions> to read
recorded arguments, order calls across doubles, and reset a double between
cases. Use <doc:ConstructionGuide> when choosing a construction path,
<doc:StubContract> when checking the supported runtime boundary, and
<doc:ManualStubbing> when a hand-written conformer is a better fit. No
construction path launches an external tool. The generated existential owns its
runtime resources and may outlive the ``Stub`` that created it.

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

- <doc:GettingStarted>
- <doc:AsyncBehaviors>
- <doc:InspectingInteractions>
- <doc:ForwardingSpies>
- <doc:StubContract>
- <doc:ManualStubbing>

### Runtime Stub API

- ``Stub``
- ``Spy``
- ``StubBuilder``
- ``StubBehaviorChain``
- ``StubSuspension``
- ``Stub/Invocation``
- <doc:FunctionValues>

### Inspecting and Ordering Interactions

- <doc:InspectingInteractions>
- ``InvocationOrder``
- ``RecordingPlaceholders``

### Recording and Replaying Interactions

- <doc:RecordAndReplay>
- ``RecordingSession``
- ``InteractionFixture``

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
- ``StubConformer``
- ``ManualMethodProxy``
- ``ManualRouteID``
- ``ManualThrowingRoute``
- ``ManualThrowingMethodProxy``

### Matching and Capture

- ``any()``
- ``any(using:)``
- ``equal(_:)``
- ``notEqual(_:)``
- ``identical(to:)``
- ``matching(description:where:)``
- ``matching(using:description:where:)``
- ``ArgumentCaptor``

### Value and Optional Matchers

- ``greaterThan(_:)``
- ``atLeast(_:)``
- ``lessThan(_:)``
- ``atMost(_:)``
- ``isNil()``
- ``notNil()``
- ``some(_:)``

### Collection Matchers

- ``isEmpty()``
- ``nonEmpty()``
- ``hasCount(_:)``
- ``hasCount(matching:)``
- ``contains(_:)``
- ``contains(where:)``
- ``containsAll(_:)``
- ``startsWith(_:)``
- ``endsWith(_:)``

### String Matchers

- ``hasPrefix(_:)``
- ``hasSuffix(_:)``
- ``containsSubstring(_:)``
- ``equalsIgnoringCase(_:)``
- ``matchesRegex(_:)``

### Composing Matchers

- ``not(_:)``
- ``allOf(_:_:)``
- ``allOf(_:_:_:)``
- ``allOf(_:_:_:_:)``
- ``anyOf(_:_:)``
- ``anyOf(_:_:_:)``
- ``anyOf(_:_:_:_:)``
- ``oneOf(_:)``

### Diagnostics and Runtime Internals

- ``StubError``
- <doc:HowRuntimeStubsWork>
- <doc:ClosureReabstractionInternals>
- <doc:TrampolineArchitecture>
