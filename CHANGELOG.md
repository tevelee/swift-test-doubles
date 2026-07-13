# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project has not published its first tagged release yet.

## Unreleased

### Added

- Metadata-driven arm64 and x86_64 runtime trampoline covering register and
  stack arguments, mixed floating-point values, throwing calls, direct
  aggregates, and indirect returns.
- Async and async-throwing protocol requirements, including genuinely
  suspending configured handlers.
- Explicit typed requirement construction when no real conformer is linked.
- Typed handlers, equality/predicate/wildcard matchers, argument capture, and
  count verification.

### Changed

- The runtime trampoline is now the package's single implementation and is
  always built; package feature traits are no longer required.
- Matcher specificity is consistent across fixed, synchronous, and suspending
  responses.
- Test fixtures live outside the public library module.
- The runtime implementation is exposed as `Stub`, with one throwing
  initializer for automatic or explicit requirement construction.
- Async behavior uses the same `then` spelling as synchronous behavior, and
  verification uses one direct `CallCount` vocabulary.
- `returns` captures one fixed value; per-call evaluation belongs to `then`.
- Unsupported existential layouts and structural protocol requirements now fail
  during construction instead of leaving invalid witness entries.
- Captors commit values only after every matcher in an invocation succeeds.

### Removed

- The hand-written conformer DSL and its duplicate recorder.
- Compiler-generated stubs and runtime `swiftc` invocation.
- Dynamic replacement compilation.
- Conditional feature traits and their strategy-specific documentation.
- The generated thunk matrix and obsolete existential-builder API.
- Module symbol-graph discovery, setup scaffolding, runtime diagnostics, and
  public low-level signature descriptors.
- Raw `[Any]` handlers and call logs, duplicate stubbing/verification aliases,
  and the incomplete order-verification API.
- Setter stubbing and protocols with coroutine-backed read-write properties;
  these cannot be fabricated safely by the current trampoline.
