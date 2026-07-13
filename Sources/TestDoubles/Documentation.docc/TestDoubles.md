# TestDoubles

Create small protocol-based test doubles without macros, generated conformers,
or per-stub compiler invocations.

## Overview

``Stub`` fabricates a protocol conformance and routes witness calls through a
fixed runtime trampoline. Configure behavior with `when`, `returns`, and `then`,
then verify the interactions that matter to the test.

```swift
let stub = try Stub<any UserRepository>()
stub.when { $0.find(id: any()) }.returns("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "Alice")

stub.verify { $0.find(id: equal(42)) }
```

The same vocabulary supports synchronous, throwing, async, and async-throwing
requirements. No construction path launches an external tool.

## Topics

### Start Here

- <doc:GettingStarted>
- <doc:StubGuide>

### Core API

- ``Stub``
- ``Stub/Requirement``
- ``Stub/CallCount``
- ``StubBuilder``
- ``StubError``

### Matching and Capture

- ``any()``
- ``equal(_:)``
- ``matching(description:where:)``
- ``ArgumentCaptor``

### Runtime Internals

- <doc:TrampolineArchitecture>
