# Contributing

Thanks for helping improve TestDoubles. Contributions are welcome, especially
focused bug fixes, tests for unsupported runtime shapes, documentation
corrections, and proposals that make failure modes safer and clearer.

By submitting a contribution, you agree that it is licensed under the
repository's [MIT License](LICENSE).

## Before you start

- Search the existing [issues](https://github.com/tevelee/swift-test-doubles/issues)
  before opening a new report.
- Use the bug form for reproducible defects and the feature form for proposed
  behavior. For a larger API, ABI, or architecture change, open an issue before
  investing in an implementation.
- Never report a suspected vulnerability in a public issue. Follow
  [SECURITY.md](SECURITY.md) and use GitHub's private vulnerability reporting.
- Create a feature branch from `main`; do not work from generated SwiftPM or
  Xcode state.

## Make a focused change

Keep commits narrow and explain public API, ABI, ownership, or concurrency
behavior when it changes. Do not commit `.build`, `.swiftpm`, `DerivedData`,
`xcuserdata`, generated DocC output, editor state, or other local build
artifacts.

Public source declarations should have documentation comments that describe
their contract and failure behavior. User-facing concepts and examples belong
in the README or DocC catalog. Runtime implementation details belong in the
[Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
reference.

## Testing tiers

Run the smallest relevant checks while iterating, then the complete baseline
before opening a pull request:

```bash
swift build
swift test --parallel
swift test -c release --parallel
Scripts/validate-documentation.sh
git diff --check
```

Swift Testing randomizes execution order when parallelization is enabled. Keep
`--parallel` explicit so local and CI runs exercise both concurrent execution
and order independence even when SwiftPM's command-line default is serial.

Changes to runtime preparation, ABI classification, executable memory,
assembly, dispatch, ownership, or concurrency also need the extended tier:

```bash
swift test --sanitize thread --scratch-path .build/tsan \
  --parallel \
  --experimental-maximum-parallelization-width 4 \
  --skip ExitTests
swift test --sanitize address --scratch-path .build/asan \
  --parallel \
  --experimental-maximum-parallelization-width 4 \
  --skip ExitTests
```

Suites whose names end in `ExitTests` still run in the baseline suites. Swift
Testing executes their process-exit closures in child processes that do not
inherit the sanitizer runtime early enough for its interceptors to initialize.
Address Sanitizer remains randomized and parallel, but its width is capped so
instrumentation cannot starve time-bounded tests.

On Apple Silicon, run the complete x86_64 package suite under Rosetta:

```bash
arch -x86_64 swift test \
  --parallel \
  --scratch-path .build/rosetta-debug \
  --triple x86_64-apple-macosx \
  --disable-xctest \
  --enable-swift-testing
arch -x86_64 swift test -c release \
  --parallel \
  --scratch-path .build/rosetta-release \
  --triple x86_64-apple-macosx \
  --disable-xctest \
  --enable-swift-testing
```

`RuntimeABITests` covers register and stack arguments, throwing calls, direct
aggregates, async continuations, and indirect results. Add a focused regression
test when changing a supported ABI shape. Handler closures remain responsible
for synchronizing their own captured mutable state.

## Code style

CI enforces `swift-format` and SwiftLint across the source and test trees.
Install both tools with Homebrew:

```bash
brew install swift-format swiftlint
```

Check the repository locally with:

```bash
swift-format lint --strict --recursive Sources Tests
swiftlint lint --strict
```

Apply automatic fixes with:

```bash
swift-format format --recursive --in-place Sources Tests
swiftlint --fix
```

The fixed-arity overloads required by the Swift compiler are checked-in generated
source. After changing their templates or supported arity, regenerate them and
verify that the working tree is current:

```bash
xcrun swift Scripts/generate-fixed-arity.swift
xcrun swift Scripts/generate-fixed-arity.swift --check
```

This maintainer-only generation does not add a build plugin or require package
consumers to generate test-double conformers.

The optional pre-commit hook applies those fixes only to staged Swift files,
rejects partially staged Swift files, and blocks the commit if strict linting
still fails. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

The hook warns and exits without blocking if either tool is unavailable. CI
reports formatting or lint violations without modifying pull-request branches.

## Open a pull request

- Target `main` and use the pull request template.
- Link the issue the change resolves and describe observable behavior, not only
  the implementation.
- Include tests for bug fixes and new behavior.
- Update source documentation, DocC, README examples, support policy, migration
  guidance, and release notes when they are affected.
- Confirm every applicable baseline, sanitizer, Rosetta, API, and documentation
  check. CI must pass before merge.

Maintainers may ask that unrelated changes be split into separate pull
requests. The README and Stub Contract define the release boundary.
