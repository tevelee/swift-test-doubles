# Swift Testing Integration

## Overview

Add `TestDoublesTesting` to a SwiftPM test target alongside `TestDoubles`, then
import both modules. `TestDoubleScope` turns double verification into a normal
Swift Testing teardown check.

```swift
import TestDoubles
import TestDoublesTesting
import Testing
```

Apply `@Test(.testDoubles)` to a single test or `@Suite(.testDoubles)` to every
test in a suite. It tracks `Stub`, `Spy`, and `ManualStub` values created in the
test task and inherited child tasks.

```swift
@Test(.testDoubles)
func checkoutUsesTheConfiguredGateway() throws {
    let gateway = try Stub<any PaymentGateway>()
    gateway.when { $0.charge(amount: 42) }.thenReturn(.approved)

    _ = try Checkout(gateway: gateway()).complete()
}
```

At teardown, the default scope reports any registration that no invocation
matched. This catches stale setup and registrations shadowed by an earlier
catch-all matcher.

Use `.strictTestDoubles` when every recorded call must also be explicitly
verified. It also reports finite behavior queues with responses left,
`thenSuspend()` calls still parked, and `CallbackCapture` values still retaining
callbacks at teardown:

```swift
@Test(.strictTestDoubles)
func checkoutHasNoSurpriseInteractions() throws {
    // ...
}
```

Name a double when several instances of the same protocol appear in a test; the
name is included in any teardown diagnostic:

```swift
let gateway = try Stub<any PaymentGateway>().named("payment gateway")
```

For a focused policy, use a `TestDoubleStrictness` option such as
`@Test(.testDoubles(strictness: .noMoreInteractions))` or
`@Test(.testDoubles(strictness: .noPendingSuspensions))`.
A double created in a `Task.detached` does not inherit the test scope; verify
that double explicitly instead. The scope reports issues at teardown but does
not consume invocations, registrations, queued responses, suspended calls, or
captured callbacks.
