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
  --filter 'RuntimeABITests|ConcurrencyTests|StubBuilderTests'

arch -x86_64 swift test \
  --package-path IntegrationTests/Consumer \
  --triple x86_64-apple-macosx \
  --disable-xctest \
  --enable-swift-testing
```

`RuntimeABITests` covers register and stack arguments, throwing calls, direct
aggregates, async continuations, and indirect results. Add focused coverage when
changing a supported ABI shape.

Runtime and concurrency changes should also pass the supported sanitizers. Use
separate scratch paths so instrumented build products do not mix:

```bash
swift test --sanitize thread --scratch-path .build/tsan
swift test --sanitize address --scratch-path .build/asan
```

The documentation examples live in a separate Swift package so they validate
the exported product exactly as a consumer sees it:

```bash
swift test --package-path IntegrationTests/Consumer
```

When changing public declarations, update [PUBLIC_API.md](PUBLIC_API.md), build
a `TestDoubles.symbols.json`, and run DocC analysis with warnings as errors:

```bash
Scripts/validate-documentation.sh
```

The same command validates repository-local documentation links and runs in
[ci.yml](.github/workflows/ci.yml).

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

See [SUPPORT.md](SUPPORT.md) for the release boundary and
[ROADMAP.md](ROADMAP.md) for the work required before `0.1.0`.
