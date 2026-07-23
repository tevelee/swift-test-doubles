# Forwarding Spies

Record calls around a real protocol implementation, with optional overrides
for the interactions a test needs to control.

## Overview

Create a ``Spy`` from a protocol and its real implementation:

```swift
let spy: Spy<any UserService> = Spy.make(forwardingTo: liveService)
let service: any UserService = spy()

#expect(service.displayName(for: "admin") == "Admin")
spy.verify { $0.displayName(for: "admin") }
```

The spy owns the target existential and uses its witness tables for signature
discovery. It does not need explicit ``Stub/Requirement`` values or a separate
linked conformer. ``Spy/make(_:forwardingTo:)`` terminates with an actionable
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

### Getter effect hints

Swift runtime metadata does not distinguish a nonthrowing getter from an
ordinary throwing getter. When the protocol has getters, preserve signature
discovery from the target's witness tables and supply that missing
classification explicitly:

```swift
let spy: Spy<any CachedProfile> = Spy.make(
    forwardingTo: liveProfile,
    getterEffects: .nonthrowing, // var cachedName: String { get }
    .throwing                    // var freshName: String { get async throws }
)
```

Supply one hint for every getter in base-first declaration order. Methods,
initializers, and setters do not consume a hint. For a composition, group hints
by the protocol that declares each getter:

```swift
let spy = try Spy<any CachedProfile & NetworkProfile>(
    forwardingTo: liveProfile,
    getterEffectsByProtocol: .effects(
        declaredBy: CachedProfile.self,
        .nonthrowing
    ),
    .effects(
        declaredBy: NetworkProfile.self,
        .throwing
    )
)
```

The hints affect calling-convention discovery only. Unmatched calls still use
the target implementation, and an override still uses the normal `when` API.
Typed-throwing getters cannot be represented by the forwarding trampoline; use
``ManualStub`` or a hand-written spy for that shape.

### Supported boundary

Forwarding uses the same runtime-generated existential and platform boundary as
``Stub``. It currently accepts synchronous, throwing, async, and
async-throwing instance methods, getters, setters, and read-write property and
subscript mutation when their arguments fit the supported register transport.
This includes inherited requirements and concretely bound associated-type
values. Getter effects cover ordinary untyped `throws`; typed-throwing getters
remain unsupported.

Compound assignment and `inout` access use the target's `_modify` coroutine.
Both legacy direct witnesses and descriptor-based public Swift 6.3 witnesses
are supported. A matching getter registration keeps the configured
writable-storage path and does not enter the target. Otherwise the spy relays
the storage yielded by the target, keeps the target alive for the entire
access, and resumes or aborts the target exactly once. Mutations and target
writeback therefore persist on both normal completion and unwind.

Swift 6.3 `read` property and subscript accessors are supported within the
synchronous, nonthrowing, borrowed-value ABI used by ``Stub``. A matching
registration still wins without entering the target. Otherwise the spy enters
the target's coroutine, relays its yielded value and borrow lifetime, and
resumes the target exactly once when the caller ends or unwinds the borrow.
Swift 6.4 protocols add a paired legacy `read` witness beside the
yielding-borrow witness. ``Spy`` construction currently rejects that pair
because forwarding the legacy `yield_once` target coroutine has not been
validated. A ``Stub`` can configure and verify the logical accessor through the
supported yielding-borrow witness.

Construction fails with ``StubError/unsupportedProtocolShape(protocolName:reason:)``
when the protocol requires any of these forwarding shapes:

- Static or initializer requirements
- Direct or optional dynamic `Self` results
- Function-valued arguments or results
- Arguments that spill to the stack or leave no registers for target metadata
- `read` coroutine descriptors outside the supported Swift 6.3 `yield_once_2`
  shape, including Swift 6.4's paired legacy `read` and yielding-borrow
  witnesses

Use a small hand-written spy when the protocol needs one of the other shapes;
construction fails before a generated value can be invoked.
