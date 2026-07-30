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
spy.when { $0.displayName(for: Match.equal("guest")) }
    .thenReturn("Test Guest")

#expect(service.displayName(for: "guest") == "Test Guest")
#expect(service.displayName(for: "admin") == "Admin")
```

A matching registration wins and does not invoke the target. If no
registration matches, the spy forwards the original arguments and result or
error through the target's witness. Both overridden and forwarded calls enter
the same invocation log, so count, ordered, eventual, and no-more-interactions
verification work across both paths.

### Override initializers explicitly

An initializer's result must retain the fabricated existential type used by the
caller, so an initializer requirement cannot transparently return the
forwarding target's distinct concrete type. Register `when(initializer:)` with
`thenInitialize()` when a test needs the initialized value to remain backed by
the spy's recorder and overrides.

### Inspect the forwarding boundary

``CallPattern/forwarded`` narrows a pattern's interaction surface to calls
that actually entered the real implementation. Its count, verification,
typed-argument, and streaming APIs mirror the pattern's ordinary interaction
APIs:

```swift
spy.when { $0.displayName(for: Match.equal("guest")) }
    .thenReturn("Test Guest")
let displayNames = spy.when {
    $0.displayName(for: Match.any())
}

#expect(service.displayName(for: "guest") == "Test Guest")
#expect(service.displayName(for: "admin") == "Admin")

displayNames.forwarded.verify(1...)
let forwarded: [String] = displayNames.forwarded.arguments()
#expect(forwarded == ["admin"])

displayNames.stubbed.verify()
let stubbed: [String] = displayNames.stubbed.arguments()
#expect(stubbed == ["guest"])
```

Both ``CallPattern/forwarded`` and ``CallPattern/stubbed`` return ordinary
``CallInteractions`` values, so each filtered view has the same count, range,
typed-argument, streaming, eventual-verification, and ``InvocationOrder`` API.
Argument and count queries are pure; `verify` explicitly marks matching calls
as verified. A call is marked forwarded when the spy selects the target; its
return value or error remains on the protocol's normal transport path.

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
async-throwing instance and static methods; getters, setters; and read-write
property and subscript mutation when their arguments fit the supported register
transport. This includes inherited requirements and concretely bound
associated-type values. Getter effects cover ordinary untyped `throws`;
typed-throwing getters remain unsupported.

Ordinary instance methods may also forward concrete, copyable
SIMD values when each value occupies one through four complete vector registers
on both arm64 and x86_64. Mixed scalar and vector arguments and all eight vector
argument registers are supported for synchronous and asynchronous calls. The
forwarding bridge preserves all lane bits in arguments and results. Smaller,
padded, more-than-four-register, nested, and dependent SIMD shapes remain
fail-closed. Synchronous forwarding remains register-only; the async stack path
additionally supports complete 16-byte, one-register vector spills.

Ordinary async instance methods, untyped-throwing or not, may forward one
through eight consecutive stack words contributed by complete one- or two-word
integers, `Float`, `Double`, or one-register SIMD arguments when the target's
dynamic-Self metadata and witness table follow on that same stack path. One
narrow integer may use the low bytes of its padded stack word. A complete
two-word integer or SIMD spill contributes two words. The bridge copies the
words before
suspension, then places them in declaration order before that hidden pair.
Immediate and suspending targets, untyped errors, and indirect result storage
share this boundary on arm64 and x86_64. A spilled `Float` uses the low four
bytes of its eight-byte stack slot. A second narrow integer, ninth word, split
or multiword padded value, smaller floating-point value, wider-vector value,
indirect argument, dependent argument, accessor, static requirement, and
typed-error stack shape remain fail-closed.

Compound assignment and `inout` access use the target's `_modify` coroutine.
Both legacy direct witnesses and descriptor-based public Swift 6.3 witnesses
are supported. A matching getter registration keeps the configured
writable-storage path and does not enter the target. Otherwise the spy relays
the storage yielded by the target, keeps the target alive for the entire
access, and resumes or aborts the target exactly once. Mutations and target
writeback therefore persist on both normal completion and unwind.

Swift 6.3 `read` and Swift 6.4 `yielding borrow` property and subscript accessors
are supported within the
synchronous, nonthrowing, borrowed-value ABI used by ``Stub``. A matching
registration still wins without entering the target. Otherwise the spy enters
the target's coroutine, relays its yielded value and borrow lifetime, and
resumes the target exactly once when the caller ends or unwinds the borrow.
Swift 6.4 protocols add a paired legacy `read` witness beside the
yielding-borrow witness. ``Spy`` explicitly forwards through the adjacent
`yield_once_2` yielding-borrow witness; source calls compiled with Swift 6.4 use
that modern entry. The fabricated witness table deliberately leaves the legacy
`yield_once` compatibility slot unavailable, so older binary clients that
dispatch through that slot cannot access that property or subscript on a
generated double.

Initializer requirements must use an explicit `when(initializer:)` override.

Construction fails with ``StubError/unsupportedProtocolShape(protocolName:reason:)``
when the protocol requires any of these other unsupported forwarding shapes:

- Direct or optional dynamic `Self` results
- Function-valued arguments or results
- Stack arguments outside the bounded synchronous and async forwarding paths
  described above
- SIMD outside the single-register 128-bit synchronous boundary, including a
  ninth vector argument
- `read` coroutine descriptors outside the supported Swift 6.3 `read2` and
  Swift 6.4 `yielding borrow` `yield_once_2` shape

Use a small hand-written spy when the protocol needs one of the other shapes;
construction fails before a generated value can be invoked.
