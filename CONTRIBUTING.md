# Contributing

## Building

```bash
swift build
swift build --traits ManualStub
swift build --traits ManualStub,RuntimeStub,CompiledStub,DynamicReplacement
```

## Running Tests

```bash
swift test                         # default traits (ManualStub + RuntimeStub)
swift test --traits ManualStub     # ManualStub only
```

`RuntimeABITests` covers the raw trampoline's register, stack, throwing, direct
aggregate, and indirect-return paths.

## Runtime Trampoline

`RuntimeStub` uses shared synchronous and asynchronous assembly capture entries
per architecture plus tiny per-slot branch veneers. The Swift handler in
`TrampolineHandler.swift` owns argument decoding, recorder dispatch, and return
encoding. Read the
[Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
reference before changing this contract.

## Branch Workflow

- Create a feature branch from `main`
- Open a pull request targeting `main`
- All relevant trait combinations must pass before merging

## Known Limitations

- **suspending async handlers**: `RuntimeStub` supports async requirements, but configured handlers complete immediately and cannot themselves suspend.
- **CompiledStub is macOS-only**: `swiftc` is not available on Linux or iOS simulators.
- **RuntimeStub on Linux**: untested — Echo's Linux support is not confirmed. `ManualStub` is the safe choice on Linux.
