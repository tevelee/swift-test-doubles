# ``TestDoubles``

Create small protocol-based test doubles without macros, generated conformers,
or per-stub compiler invocations.

## Overview

``Stub`` fabricates a protocol conformance and routes witness calls through a
fixed runtime trampoline. Configure behavior with `when`, `thenReturn`,
`thenThrow`, and `then`, then verify the interactions that matter to the test.

Use ``Dummy`` when an API requires a protocol value that the exercised code path
must not use. A dummy has no behavior or recorder, and every invocation fails
closed with an actionable diagnostic.

Start with <doc:GettingStarted> for task-oriented examples. Use
<doc:ConstructionGuide> when choosing a construction path, <doc:StubContract>
when checking the supported runtime boundary, and <doc:ManualStubbing> when a
hand-written conformer is a better fit. No construction path launches an
external tool. The generated existential owns its runtime resources and may
outlive the ``Stub`` that created it.

Runtime stubs support synchronous, throwing, async, and async-throwing
requirements, inherited protocols, protocol compositions, direct property and
subscript setters, class-constrained protocols, `NSObject`-backed superclass
constraints, bounded primary-associated-type bindings across supported
inheritance and compositions, caller-supplied bindings for covariant associated
results, recording-result placeholders, direct and optional dynamic `Self`
results, initializer requirements, sequenced responses, immediate and eventual
verification, invocation clearing, and unverified-interaction reporting.
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
- <doc:StubContract>
- <doc:ManualStubbing>

### Runtime Stub API

- ``Stub``
- ``makeStub(_:)-7h3si``
- ``makeStub(sendability:_:)``
- ``StubSendability``
- ``StubBuilder``
- ``Stub/Invocation``
- <doc:FunctionValues>

### Dummy API

- ``Dummy``
- ``makeDummy(_:)``
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
- ``matching(description:where:)``
- ``matching(using:description:where:)``
- ``ArgumentCaptor``

### Diagnostics and Runtime Internals

- ``StubError``
- <doc:HowRuntimeStubsWork>
- <doc:ClosureReabstractionInternals>
- <doc:TrampolineArchitecture>
