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
- Compiled public-API examples for matcher specificity, argument capture,
  suspending async success and failure, and stateful responses.
- A clean consumer-package suite and CI gates for the minimum/current Swift
  toolchains, release builds, DocC, and Rosetta x86_64.
- Support and private vulnerability-reporting policies.
- Workflow linting, public-repository CodeQL analysis, Dependabot security and
  version updates, and check-gated Dependabot auto-merge for all update sizes.

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
- Automatic discovery resolves concrete type metadata before allocation, and
  explicit requirements are checked against every reliably discoverable
  component of a linked conformance.
- `requirementKindMismatch` is now the more general `requirementMismatch`, which
  reports discoverable kind, type, and effect mismatches.
- The unsupported x86_64 six-register async continuation boundary now fails
  during construction.
- Captors commit values only after every matcher in an invocation succeeds.
- Async dispatch preserves task-local state, cancellation, priority, handler
  actor isolation (including when the actor uses a custom serial executor), and
  actor-isolated caller executor resumption.
- The CI-backed release boundary covers macOS 13+, Mac Catalyst 16+, and arm64
  Simulators for iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+, with runtime
  execution on arm64 and macOS x86_64. Linux is outside the `0.1.0` support
  boundary.
- Public API changes are enforced by a canonical, checked-in symbol-graph
  snapshot.
- The reproducible release checklist validates dependency resolution, public
  API, documentation, debug/release builds, and an external consumer.
- The README and Getting Started guide now showcase the same task-oriented
  matching, capture, async, stateful-response, and explicit-construction
  scenarios.
- DocC now separates task-oriented examples, the supported Stub contract, and
  runtime architecture into curated, cross-linked pages.

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
- The dedicated function-value error case; unsupported function requirements now
  use the general protocol-shape construction error.
