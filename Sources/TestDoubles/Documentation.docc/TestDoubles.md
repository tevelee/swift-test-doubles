# TestDoubles

Create protocol-based Swift test doubles without macros, generated conformer
source, or per-stub `swiftc` compilation.

## Overview

``RuntimeStub`` fabricates a protocol conformance and routes witness calls
through a runtime trampoline. Configure fixed or dynamic behavior with `when`,
`returns`, and `then`; match or capture arguments; then verify the interactions
that matter to the test.

```swift
let stub = RuntimeStub<any UserRepository>()
stub.when { $0.find(id: any()) }.returns("Alice")

let repository: any UserRepository = stub()
let user = repository.find(id: 42)

stub.verify { $0.find(id: equal(42)) }.wasCalled()
```

The same API supports synchronous, throwing, async, and async-throwing protocol
requirements. Async handlers may suspend on the caller's task.

Zero-configuration construction discovers signatures from a real conformer
linked into the test binary. When one is unavailable, use module discovery or
explicit typed ``Slot`` descriptions. Module discovery launches
`swift symbolgraph-extract` from the host toolchain; the other two paths do not
launch external tools.

## Topics

### Start Here

- <doc:GettingStarted>
- <doc:RuntimeStub>

### Runtime Internals

- <doc:TrampolineArchitecture>

### Core API

- ``RuntimeStub``
- ``Slot``
- ``DiscoveredSignature``

### Matching and Capture

- ``any()``
- ``equal(_:)``
- ``ArgumentCaptor``
- ``ParameterMatcher``
