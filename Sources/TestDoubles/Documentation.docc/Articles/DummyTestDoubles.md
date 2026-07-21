# Dummy Test Doubles

Pass a required dependency to a code path that must not use it.

## Overview

A dummy satisfies an API's type requirements without supplying behavior. Use
``makeDummy(_:)`` when the scenario under test requires a protocol argument but
should not invoke any of its requirements:

```swift
protocol AnalyticsClient {
    func track(event: String)
}

func title(analytics: any AnalyticsClient) -> String {
    "Welcome"
}

let result = title(analytics: makeDummy(AnalyticsClient.self))
```

`Dummy` uses runtime protocol metadata to fabricate the existential and the
same architecture-specific witness trampolines as ``Stub``. It does not
discover argument or result signatures, create a recorder, accept configured
behavior, or expose verification. This lets it represent protocol requirements
whose values are outside the stub marshalling boundary, including function and
SIMD values, as long as the requirements are never invoked.

Every supported callable witness, including async requirements and `_modify`
property access, points to a fail-closed trampoline. An invocation terminates the process
with a diagnostic identifying the declaring protocol and witness index. If the
dependency is expected to respond or if the test needs to verify an
interaction, use ``Stub`` instead.

Swift 6.3 `read` accessors are result-dependent borrowed coroutines and are not
fabricated for Dummy. Construction rejects a protocol containing one; use a
Stub with configured getter behavior or a hand-written dummy.

The generated protocol value owns its fabricated witness tables and page-backed
executable trampoline arena. It remains valid after the `Dummy` instance is
released.

### Construction boundary

``makeDummy(_:)`` and ``Dummy/init()`` accept ordinary opaque and
class-constrained Swift protocol existentials, compositions, inheritance, and
concretely bound associated types within the protocol-layout boundary shared
with ``Stub``. The initializer throws ``StubError`` for non-protocol types and
unsupported existential or protocol metadata shapes. The factory fails closed
with the same error rendered as an actionable construction diagnostic.
