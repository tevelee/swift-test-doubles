# Roadmap to 0.1.0

This roadmap turns TestDoubles into a small, production-oriented package built
around one implementation: a runtime protocol stub backed by a trampoline. The
release target is an honest macOS-first `0.1.0`, with a narrow documented API,
explicitly tested ABI coverage, and no compiler-at-test-time or duplicate
manual-stub systems.

## North star

- One package product and one protocol-stub implementation.
- One recorder and one runtime trampoline backend.
- One vocabulary for configuration, matching, capture, and verification.
- Unsupported protocol shapes fail during stub construction with actionable
  diagnostics.
- Every documented capability is exercised by a motivating test and a public
  example.
- Platform claims reflect CI coverage rather than assumptions.

The intended public center of gravity is eventually `Stub<P>`, configured with
`when`, `returns`, and one `then` family, then inspected with `verify`. The
existing `RuntimeStub` name remains during the mechanical collapse so naming and
behavior changes do not land in the same iteration.

## Iteration 1 — Collapse to one implementation

**Status:** Complete

- **Objective:** Make the runtime trampoline the only implementation without
  changing its behavior or public spelling.
- **Mode:** Mechanical deletion and dependency cleanup.
- **Owned files:** `Package.swift`, obsolete implementation and test files,
  conditional-compilation guards, package overview documentation.
- **Dependencies:** None.
- **Invariants:** `RuntimeStub` behavior and its current public entry points
  remain available; `MockRegistry` and the C trampoline remain intact.
- **Out of scope:** Renaming `RuntimeStub`, redesigning explicit requirements,
  pruning duplicate runtime API spellings, platform policy changes.
- **Required checks:** Debug and release tests, focused Rosetta ABI tests, DocC
  conversion, stale-symbol search, and `git diff --check`.
- **Integration notes:** Remove package traits, `ManualStub`, `CompiledStub`,
  runtime compiler/source generation, dynamic replacement, and their tests and
  articles. Remove only the outer runtime feature guards from surviving code.
- **Done criteria:** The package always builds the runtime implementation, no
  deleted strategy is referenced as a supported feature, and all required
  checks pass.

## Iteration 2 — Freeze the minimum public API

**Status:** Planned

- **Objective:** Give the surviving implementation its smallest coherent API.
- **Mode:** Public API review and focused refactor.
- **Owned files:** Runtime stub construction, builders, verification, signature
  discovery/tooling, public documentation, API snapshot.
- **Dependencies:** Iteration 1.
- **Invariants:** Supported protocol calls and handler behavior remain covered
  by tests; migration notes accompany every removal or rename.
- **Out of scope:** New platform claims and executor customization.
- **Required checks:** Public symbol-graph diff, debug/release tests, migration
  examples, DocC with no unresolved links.
- **Integration notes:** Rename `RuntimeStub` to `Stub`; prefer a single
  throwing construction model; replace the current explicit
  `Slot`/`MethodDescriptor` surface with one typed requirement description;
  remove module symbol-graph extraction, setup scaffolding, diagnostics objects,
  and duplicate spellings such as `thenAsync` where `then` can express the same
  behavior. Review verification aliases, raw call exposure, proxies, and public
  matcher internals for removal.
- **Done criteria:** A checked-in public API snapshot contains only the agreed
  construction, stubbing, matching, capture, and verification vocabulary.

## Iteration 3 — Harden the supported contract

**Status:** Planned

- **Objective:** Turn the runtime behavior into an explicit, enforceable product
  contract.
- **Mode:** Runtime hardening and platform decision.
- **Owned files:** Trampoline preparation and dispatch, executor handling, ABI
  tests, package platform declarations, limitations documentation.
- **Dependencies:** Iteration 2.
- **Invariants:** Unsupported signatures fail before the subject is invoked;
  concurrent calls remain safe after serial setup.
- **Out of scope:** Platforms without repeatable runtime CI.
- **Required checks:** arm64 debug/release tests, Rosetta tests, concurrency
  stress tests, custom-executor tests, and sanitizer checks where supported.
- **Integration notes:** Add custom `SerialExecutor` coverage and support; either
  fix the x86_64 six-integer async boundary or document and enforce its rejection.
  Declare macOS as the initial supported platform. Add iOS or Linux only after
  they have real runtime execution coverage.
- **Done criteria:** The supported signature/platform matrix is tested, checked
  during construction, and documented from the same source of truth where
  practical.

## Iteration 4 — Teach the product through examples

**Status:** Planned

- **Objective:** Make the package understandable and useful without reading its
  implementation.
- **Mode:** Documentation and test consolidation.
- **Owned files:** README, DocC articles, motivating use-case tests, duplicate
  low-level tests.
- **Dependencies:** Iteration 3.
- **Invariants:** Documentation examples compile and demonstrate only supported
  APIs.
- **Out of scope:** Expanding the feature set to create more examples.
- **Required checks:** Compiled snippets, DocC with zero warnings, full tests,
  link validation.
- **Integration notes:** Center examples on repository matching, async success
  and failure, genuinely suspending handlers, argument capture for side effects,
  and stateful responses. Organize docs as Quick Start, Common Patterns,
  Supported Features, Explicit Requirements, Limitations, and Architecture.
- **Done criteria:** Each promised capability has one concise public example and
  one motivating test; redundant tests and stale implementation narratives are
  removed.

## Iteration 5 — Release engineering

**Status:** Planned

- **Objective:** Make a clean consumer checkout safe to adopt and maintain.
- **Mode:** Release preparation.
- **Owned files:** CI workflows, changelog, support/security policy, dependency
  pins, release checklist, API snapshot.
- **Dependencies:** Iteration 4.
- **Invariants:** No release claim exceeds automated coverage.
- **Out of scope:** Features not required by the documented `0.1.0` contract.
- **Required checks:** Clean external-consumer integration, CI across supported
  architectures and configurations, release build, API snapshot verification,
  DocC build.
- **Integration notes:** Move dependencies to appropriate tagged releases,
  write the changelog from the actual first tag boundary, publish support and
  security expectations, and tag `0.1.0` only after the release checklist is
  reproducible.
- **Done criteria:** A fresh consumer can add the tagged package, compile every
  documented example, run the supported test matrix, and understand the support
  policy without repository-specific knowledge.

## Release-ready definition

`0.1.0` is ready when Iterations 1–5 are complete, the working tree is clean,
the public API snapshot is intentional, DocC emits no warnings, every platform
claim is backed by CI, limitations are construction-time errors where possible,
and the README's examples pass as consumer integration tests.
