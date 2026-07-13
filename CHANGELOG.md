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
- Module-based and explicit typed signature construction when no real conformer
  is linked.
- Typed matchers, handlers, argument capture, and verification.

### Changed

- The runtime trampoline is now the package's single implementation and is
  always built; package feature traits are no longer required.
- Matcher specificity is consistent across fixed, synchronous, and suspending
  responses.
- Test fixtures live outside the public library module.

### Removed

- The hand-written conformer DSL and its duplicate recorder.
- Compiler-generated stubs and runtime `swiftc` invocation.
- Dynamic replacement compilation.
- Conditional feature traits and their strategy-specific documentation.
- The generated thunk matrix and obsolete existential-builder API.
