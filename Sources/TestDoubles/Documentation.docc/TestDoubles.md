# TestDoubles

A Swift testing library with three stub strategies — pick the one that fits your constraints.

## Overview

TestDoubles gives you protocol-based test doubles without macros or code generation. Choose your strategy based on platform, test architecture, and how much boilerplate you're willing to write:

| | ManualStub | RuntimeStub | CompiledStub |
|---|---|---|---|
| **Platform** | All | All | macOS only |
| **Requires conformer in binary** | No | Yes | No |
| **Requires Echo** | No | Yes | Yes (via RuntimeStub) |
| **Test startup overhead** | None | None | ~1–2 s compile |
| **Protocol access needed** | Yes (write struct) | No | No |

### Which strategy should I use?

- Use **ManualStub** when you want zero dependencies, full control, and are happy writing a small conforming struct.
- Use **RuntimeStub** when you want zero configuration and your test binary already links the conformer (i.e., the real implementation is in the same binary or a linked framework).
- Use **CompiledStub** on macOS when the protocol lives in a pre-compiled module with no accessible conformer — the library compiles a stub at test startup.

## Topics

### Strategies

- <doc:ManualStub>
- <doc:RuntimeStub>
- <doc:CompiledStub>

### Matching Arguments

- ``any()``
- ``equal(_:)``
- ``ArgumentCaptor``

### Manual Stub API

- ``StubConformer``
- ``Stub``

### Runtime Stub API

- ``RuntimeStub``
- ``DiscoveredSignature``
- ``Slot``

### Extensibility

- ``ParameterMatcher``
