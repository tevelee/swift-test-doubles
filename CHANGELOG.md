# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- Metadata-driven arm64 and x86_64 runtime trampoline with arbitrary arity, throwing calls, mixed floating-point arguments, and indirect returns
- RuntimeStub support for async and async-throwing protocol requirements with immediate configured responses
- Module-based signature discovery and fabricated RuntimeStub conformances
- Reusable typed matchers, typed handlers, and typed argument inspection
- Opt-in dynamic replacement compiler support

### Changed
- Test fixtures moved out of the public library module
- Dynamic replacement has an independent package trait
- RuntimeStub diagnostics and documentation now describe the trampoline backend directly

### Removed
- Generated thunk matrix and obsolete existential-builder API

## [1.0.0] - 2026-04-06

### Added
- Three isolated stub strategies: `ManualStub`, `RuntimeStub`, `CompiledStub`
- Swift 6.1 package traits for opt-in dependency on Echo
- `CompiledStub<P>` — separate type from `RuntimeStub`, compiles conformances via `swiftc` at test startup
- `RuntimeStub<P>` — zero-config witness table patching via the Echo package
- `Stub<T>` — manual conformer base with `@dynamicMemberLookup` forwarding
- Full DocC documentation catalog with Getting Started guide and per-strategy articles
- Argument matchers: `any()`, `equal(_:)`, `any(where:)`, `ArgumentCaptor`
- Verification API: `wasCalled()`, `wasCalled(times:)`, `wasNotCalled()`, `withArgs(_:)`
- Concise verification forms: `verify(called:)`, `verify(never:)`
- Order verification: `verifyOrder { }`
- Trailing closure stubbing style: `stub.when { } then: { }`
- Async and throwing method support
- `RuntimeStub.diagnose()` for human-readable setup failure reporting
- Thread-safe matcher context via `MatcherContext`
