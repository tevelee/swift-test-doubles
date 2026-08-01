# Dummy Test Doubles

Pass any safely constructible value to a code path that must not use it.

## Overview

A dummy satisfies an API's type requirements without supplying meaningful
content or behavior. ``Dummy/make(_:)`` supports protocol existentials,
functions, and concrete values whose storage can be initialized safely:

```swift
protocol AnalyticsClient {
    func track(event: String)
}

struct CheckoutContext {
    let attempt: Int
    let labels: [String]
}

func title(
    analytics: any AnalyticsClient,
    context: CheckoutContext,
    completion: (String) -> Void
) -> String {
    "Welcome"
}

let result = title(
    analytics: Dummy.make(),
    context: Dummy.make(),
    completion: Dummy.make()
)
```

Concrete dummy contents are deliberately unspecified. Do not assert on them or
pass a dummy to a path that reads them.

### Protocol existentials

For a protocol existential, `Dummy` uses runtime protocol metadata to fabricate
the existential and the same architecture-specific witness trampolines as
``Stub``. It does not discover argument or result signatures, create a recorder,
accept configured behavior, or expose verification. This lets it represent
protocol requirements whose values are outside the stub marshalling boundary,
including function and SIMD values, as long as the requirements are never
invoked.

Every supported callable witness, including async requirements and `_modify`
property access, points to a fail-closed trampoline. An invocation terminates
the process with a diagnostic identifying the declaring protocol and witness
index. If the dependency is expected to respond or if the test needs to verify
an interaction, use ``Stub`` instead.

Descriptor-based Swift 6.3 `read` accessors can be present on an unused Dummy.
Their fabricated entry rejects through the normal Dummy diagnostic before it
can yield or resume a value. Descriptor-based `_modify`, Swift 6.4 `yielding
borrow`, and legacy direct coroutine witnesses retain their documented
fail-closed boundaries.

The generated protocol value owns its fabricated witness tables and page-backed
executable trampoline arena. It remains valid after the `Dummy` instance is
released.

### Concrete values

Automatic concrete synthesis builds initialized Swift values rather than
returning arbitrary memory. It supports:

- scalar numeric and Boolean values, strings, metatypes, `Any`, and `AnyObject`;
- empty arrays, sets, and dictionaries;
- tuples and structs when every stored value is synthesizable;
- enums with an empty case, or with a direct payload case whose payload is
  synthesizable; and
- escaping Swift functions, thin functions, C function pointers, and Objective-C
  blocks where available, including async, throwing, typed-throwing, and
  `@Sendable` Swift function types.

Function values point to a fail-closed body. Invoking one terminates with a
dummy diagnostic. Function fields nested inside tuples, structs, and direct
enum payloads use the same behavior.

Automatic synthesis rejects an uninhabited enum, indirect recursive enum,
arbitrary concrete class, or aggregate containing another unsupported value.
Use ``Dummy/init(using:)`` or ``Dummy/make(_:using:)`` to supply one valid
placeholder at the call site:

```swift
let session: Session = Dummy.make(using: {
    Session(identifier: "unused")
})
```

When the same exact type appears throughout a suite, register its factory once:

```swift
Dummy<Session>.register {
    Session(identifier: "unused")
}
defer { Dummy<Session>.unregister() }

let session: Session = Dummy.make()
```

The registry is process-global. The latest exact-type registration wins and
takes precedence over automatic synthesis, so avoid changing the same type's
registration from parallel tests.

### Construction boundary

Protocol construction accepts ordinary opaque and class-constrained Swift
protocol existentials, compositions, inheritance, and concretely bound
associated types within the protocol-layout boundary shared with ``Stub``.
Concrete construction is available wherever the runtime can produce a fully
initialized value using the rules above.

``Dummy/init()`` throws ``StubError`` when neither path can construct the type.
``Dummy/make(_:)`` fails closed with the same error rendered as an actionable
diagnostic. Supplying or registering a factory is the safe recovery for a
concrete type outside the automatic boundary.
