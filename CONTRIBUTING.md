# Contributing

## Building and testing

Run the package's debug and release suites before opening a pull request:

```bash
swift build
swift test
swift test -c release
```

On Apple Silicon, also exercise the x86_64 trampoline under Rosetta when a
change touches runtime preparation, ABI classification, assembly, or dispatch:

```bash
arch -x86_64 swift test \
  --triple x86_64-apple-macosx \
  --disable-xctest \
  --enable-swift-testing \
  --filter 'RuntimeABITests|StubBuilderTests|PublicAPITests'
```

`RuntimeABITests` covers register and stack arguments, throwing calls, direct
aggregates, async continuations, and indirect results. Add focused coverage when
changing a supported ABI shape.

When changing public declarations, update [PUBLIC_API.md](PUBLIC_API.md) and
compare it with a public symbol graph:

```bash
xcrun swift package dump-symbol-graph \
  --minimum-access-level public \
  --skip-synthesized-members
```

## Runtime trampoline

`Stub` uses shared synchronous and asynchronous assembly capture entries
per architecture plus tiny per-slot branch veneers. The Swift handler in
`TrampolineHandler.swift` owns argument decoding, recorder dispatch, and return
encoding. Read the
[Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
reference before changing this contract.

Stub configuration and verification are serial operations. Once configured,
normal invocation and call-log storage are lock-protected and may be concurrent;
handler closures remain responsible for their own captured mutable state.

## Branch workflow

- Create a feature branch from `main`.
- Keep commits focused and explain public API or ABI behavior changes.
- Open a pull request targeting `main`.
- Run all checks relevant to the changed runtime paths.

## Current release boundaries

- macOS arm64 and Rosetta x86_64 are the exercised runtime environments.
- iOS and Linux are not release-supported until real runtime CI exists.
- Closure requirements need compiler-generated reabstraction and are rejected;
  use a hand-written test double for such protocols.
- x86_64 construction rejects async signatures that consume all six
  general-purpose argument registers.

See [ROADMAP.md](ROADMAP.md) for the work required before `0.1.0`.
