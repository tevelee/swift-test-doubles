# Contributing

## Building

```bash
swift build
swift build --traits ManualStub
swift build --traits ManualStub,RuntimeStub,CompiledStub
```

## Running Tests

```bash
swift test                         # default traits (ManualStub + RuntimeStub)
swift test --traits ManualStub     # ManualStub only
```

`RuntimeABITests` covers the raw trampoline's register, stack, throwing, direct
aggregate, and indirect-return paths.

## Runtime Trampoline

`RuntimeStub` uses a fixed assembly capture stub per architecture plus tiny per-slot branch veneers. The Swift handler in `TrampolineHandler.swift` owns argument decoding, recorder dispatch, and return encoding.

## Branch Workflow

- Create a feature branch from `main`
- Open a pull request targeting `main`
- CI must pass before merging

## Known Limitations

- **async requirements**: `RuntimeStub` rejects async witness entries. Use `ManualStub` or macOS-only `CompiledStub`.
- **CompiledStub is macOS-only**: `swiftc` is not available on Linux or iOS simulators.
- **RuntimeStub on Linux**: untested — Echo's Linux support is not confirmed. `ManualStub` is the safe choice on Linux.
