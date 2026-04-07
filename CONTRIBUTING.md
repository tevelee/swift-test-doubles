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

The `paymentGatewayChargeAndRefund` test is disabled — it exercises a `struct` with a return value > 16 bytes, which exceeds the ABI limit of the pre-generated thunks. This is a known limitation, not a bug to fix here.

## Regenerating ThunkLibrary

The `ThunkLibrary.swift` file is auto-generated. After changing the thunk generation script:

```bash
swift run --package-path Scripts GenerateThunks
```

The output is written to `Sources/TestDoubles/ThunkLibrary.swift`. Commit the updated file.

## Branch Workflow

- Create a feature branch from `main`
- Open a pull request targeting `main`
- CI must pass before merging

## Known Limitations

- **sret ABI**: `RuntimeStub` thunks support return values ≤ 16 bytes. Structs larger than 16 bytes need sret thunk variants (not yet generated). Use `ManualStub` or `CompiledStub` for such protocols.
- **CompiledStub is macOS-only**: `swiftc` is not available on Linux or iOS simulators.
- **RuntimeStub on Linux**: untested — Echo's Linux support is not confirmed. `ManualStub` is the safe choice on Linux.

## Adding a New Thunk Variant

Thunks are generated in `Scripts/generate_thunks.swift`. To add an sret (indirect-return) variant:

1. Add a new `ThunkKind` case (e.g. `.sret`)
2. Emit the corresponding ARM64 / x86-64 assembly stub
3. Update `ThunkLibrary.lookupThunk(for:)` to select the new variant when the return type size exceeds 16 bytes
4. Regenerate and run tests
