# Reusable Scenarios

Compose named, reusable test-double setup without a second stubbing DSL.

## Overview

Use `StubScenario` to give a repeated bit of test setup a name without hiding
the familiar `when`/`then` syntax. A scenario applies to an existing `Stub`,
which leaves construction, verification, and argument capture in the test that
uses it.

```swift
let signedOutUser: StubScenario<any AccountService> = .init {
    $0.when { $0.currentUser() }.thenReturn(nil)
    $0.when { $0.canPurchase() }.thenReturn(false)
}

let stub = try Stub<any AccountService>()
signedOutUser.apply(to: stub)
```

Scenarios compose in registration order. Since stubs are first-match-wins,
append specific registrations before broad fallbacks:

```swift
let member: StubScenario<any AccountService> = .init {
    $0.when { $0.user(id: equal(42)) }.thenReturn(sampleMember)
}
let fallback: StubScenario<any AccountService> = .init {
    $0.when { $0.user(id: any()) }.thenReturn(nil)
}

member.appending(fallback).apply(to: stub)
```

`ManualStubScenario` applies the same kind of setup to a hand-written
conformer. For configurations that record async requirements, use
`AsyncStubScenario` or `AsyncManualStubScenario` and await `apply(to:)`.
