# ``TestDoubles``

Create small protocol-based test doubles without macros, generated conformers,
or per-stub compiler invocations.

## Overview

``Stub`` fabricates a protocol conformance and routes witness calls through a
fixed runtime trampoline. Configure behavior with `when`, `returns`, and `then`,
then verify the interactions that matter to the test.

The same vocabulary supports synchronous, throwing, async, and async-throwing
requirements. Start with <doc:GettingStarted> for task-oriented examples, then
use <doc:StubContract> as the supported contract reference. No construction path
launches an external tool.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:StubContract>

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
