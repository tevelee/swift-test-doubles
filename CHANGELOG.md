# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- WatchOS simulator support
- Explicit `thenDoNothing()` behavior for `Void`-returning stub requirements;
  `when` now requires a terminal behavior, so ignoring its builder produces a
  compiler warning and no longer installs an implicit `Void` fallback.
- Chainable fixed returns, errors, and no-ops for consecutive matching
  invocations, with the final configured behavior repeating.
- `makeSpy(_:forwardingTo:)` for fail-fast construction of a forwarding spy
  that remains available for stubbing and verification.
- Typed-throws forwarding for `ManualStub` through the explicit
  `throwing:` overloads of `throwingCall` and `asyncThrowingCall`.

### Changed

- Recoverable `Stub`, `Dummy`, and `Spy` constructors now declare
  `throws(StubError)`; the corresponding `makeStub`, `makeDummy`, and `makeSpy`
  factories remain fail-fast conveniences.
- The `makeSpy` protocol metatype parameter defaults to the contextual type,
  so the existential can come from the result annotation:
  `let spy: Spy<any P> = makeSpy(forwardingTo: live)`. Without an annotation
  or explicit metatype, the forwarding target's concrete type is inferred and
  construction fails fast with a protocol-existential diagnostic. Spy
  construction also accepts flat or declaration-grouped getter-effect hints.
- Fabricated witness identities are retained for process-stable cache identity
  only after successful construction; failed construction releases its
  temporary witness allocations.

## [0.0.1] - 2026-07-18

### Added

- Runtime-generated `Stub` and fail-closed `Dummy` values for supported Swift
  protocol shapes, with no macros or generated conformers.
- Synchronous, throwing, async, typed-throwing, initializer, property,
  subscript, dynamic `Self`, protocol-composition, and bounded
  primary-associated-type support across the documented runtime boundary.
- Fixed, sequenced, and handler-based behavior; argument matching and capture;
  immediate, eventual, ordered, and unverified-interaction checks.
- `ManualStub` for protocols and platforms outside the runtime trampoline's
  supported boundary.
- CI workflows for the documented macOS, Linux, simulator, and Mac Catalyst
  matrix, including watchOS Simulator, release-mode, and x86_64 runtime checks.

### Security

- Runtime and ABI boundaries fail closed when a protocol requirement cannot be
  represented safely.

[Unreleased]: https://github.com/tevelee/swift-test-doubles/commits/main
[0.0.1]: https://github.com/tevelee/swift-test-doubles/tree/0.0.1
