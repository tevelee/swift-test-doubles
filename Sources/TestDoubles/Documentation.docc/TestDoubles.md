# TestDoubles

A Swift testing library with three protocol-stub strategies, plus dynamic replacement support when you control the implementation build.

## Overview

TestDoubles gives you protocol-based test doubles without macros or code generation. Choose your strategy based on platform, test architecture, and how much boilerplate you're willing to write:

| | ManualStub | RuntimeStub | CompiledStub |
|---|---|---|---|
| **Platform** | All | Apple arm64/x86_64; Linux unverified | macOS only |
| **Requires conformer in binary** | No | Zero-config only | No |
| **Requires Echo** | No | Yes | Yes (via RuntimeStub) |
| **Test startup overhead** | None | None | ~1–2 s compile |
| **Protocol access needed** | Yes (write struct) | No | No |

### Which strategy should I use?

- Use **ManualStub** when you want zero dependencies, full control, and are happy writing a small conforming struct.
- Use **RuntimeStub** when you want zero configuration and your test binary already links a conformer, or when the protocol's Swift module can provide signatures and you want no compile step.
- Use **CompiledStub** on macOS when the protocol lives in a pre-compiled module with no accessible conformer — the library compiles a stub at test startup.
- Use **DynamicReplacementCompiler** when you control the implementation build and need to replace concrete functions or methods rather than protocol witness calls.

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:StrategyGuide>

### Strategies

- <doc:ManualStub>
- <doc:RuntimeStub>
- <doc:CompiledStub>
- <doc:DynamicReplacement>

### Matching Arguments

- ``any()``
- ``equal(_:)``
- ``ArgumentCaptor``

### Manual Stub API

- ``StubConformer``
- ``Stub``

### Runtime Stub API

- ``RuntimeStub``
- ``DynamicReplacementCompiler``
- ``DiscoveredSignature``
- ``Slot``

### Extensibility

- ``ParameterMatcher``
