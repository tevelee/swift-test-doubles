# Forwarding Spies

Record calls around a real protocol implementation, with optional overrides
for the interactions a test needs to control.

## Overview

Create a ``Spy`` from a protocol and its real implementation:

```swift
let spy = makeSpy(UserService.self, forwardingTo: liveService)
let service: any UserService = spy()

#expect(service.displayName(for: "admin") == "Admin")
spy.verify { $0.displayName(for: "admin") }
```

The spy owns the target existential and uses its witness tables for signature
discovery. It does not need explicit ``Stub/Requirement`` values or a separate
linked conformer. ``makeSpy(_:forwardingTo:)`` terminates with an actionable
diagnostic when construction is unsupported. Use the throwing
``Spy/init(forwardingTo:)`` initializer when the caller needs to recover and
choose a hand-written spy.

### Override selected calls

Use the same matching and response API as ``Stub``:

```swift
spy.when { $0.displayName(for: equal("guest")) }
    .thenReturn("Test Guest")

#expect(service.displayName(for: "guest") == "Test Guest")
#expect(service.displayName(for: "admin") == "Admin")
```

A matching registration wins and does not invoke the target. If no
registration matches, the spy forwards the original arguments and result or
error through the target's witness. Both overridden and forwarded calls enter
the same invocation log, so count, ordered, eventual, and no-more-interactions
verification work across both paths.

### Share target state

Class-constrained targets receive calls on the same object passed to
`init(forwardingTo:)`. Opaque value targets live in storage owned by the spy,
so mutations performed by forwarded requirements persist for later forwarded
calls.

### Supported boundary

Forwarding uses the same runtime-generated existential and platform boundary as
``Stub``. It currently accepts synchronous, throwing, async, and
async-throwing instance methods and read-only getters when their
arguments fit the supported register transport. This includes inherited
requirements and concretely bound associated-type values.

Construction fails with ``StubError/unsupportedProtocolShape(protocolName:reason:)``
when the protocol requires any of these forwarding shapes:

- Static or initializer requirements
- Direct or optional dynamic `Self` results
- Function-valued arguments or results
- Arguments that spill to the stack or leave no registers for target metadata
- `_modify` coroutines used by compound assignment and `inout` access

Use a small hand-written spy when the protocol needs one of the other shapes;
construction fails before a generated value can be invoked.
