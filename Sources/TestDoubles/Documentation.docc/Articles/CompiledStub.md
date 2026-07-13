# CompiledStub

Compile a conforming type at test startup using `swiftc` — no real conformer required.

## Overview

CompiledStub invokes the Swift compiler at test startup to synthesize a concrete type that conforms to your protocol. The generated type calls `MockBridge` for every method, routing dispatch back into the same `StubRecorder` infrastructure used by RuntimeStub.

**When to use CompiledStub:**
- The protocol lives in a pre-compiled framework your tests import but don't link a concrete type for.
- `RuntimeStub` fails with `noConformanceFound` because no conformer is in the binary.
- You're on **macOS**. This package currently gates CompiledStub to macOS
  because it uses `Process`, `dlopen`, and host build-product discovery there.

**Requirement:** macOS. The `CompiledStub` trait automatically enables `RuntimeStub`.

**Overhead:** The first use per protocol triggers a `swiftc` invocation — typically 1–2 seconds. Subsequent uses within the same test run are free (the dylib is cached).

For the full decision matrix, see <doc:StrategyGuide>.

## Installation

CompiledStub is opt-in:

```swift
// Package.swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["ManualStub", "RuntimeStub", "CompiledStub"]
)
```

## Quick Start

```swift
// No conformer needed — the library compiles one for you
let stub = try CompiledStub<any PrototypeCalculator> {
    $0.method("add",      args: [.int(), .int()], returns: .int)
    $0.method("describe", args: [.int()],          returns: .string)
    $0.getter("precision", type: .int)
}

stub.when { $0.add(1, 2) }.returns(3)
stub.when { $0.precision }.returns(10)

let sut: any PrototypeCalculator = stub()
assert(sut.add(1, 2) == 3)
```

If a real conformer already exists in the binary, you can skip the signature builder and let the library discover the methods automatically:

```swift
let stub = try CompiledStub<any MyService>()
```

## Tradeoffs

CompiledStub is the highest-fidelity protocol strategy because the generated
conformance is Swift code. Swift gives generated async, throwing, and ordinary
requirements their native calling conventions.

The tradeoff is operational: the test process must run on macOS with a Swift
toolchain that can import the same modules as the test target. The first
compile for a generated source costs process startup and compiler time.

Use CompiledStub when:

- no real conformer exists
- the protocol uses requirements outside RuntimeStub's raw ABI coverage
- RuntimeStub cannot resolve the metadata or ABI shape
- you are already running tests on macOS

Prefer ManualStub or RuntimeStub when:

- tests must run on Linux or device-only environments
- the protocol is small enough to write manually
- runtime compiler setup is not worth the cost

## Signature Builder Tips

Use the exact protocol requirement names and labels:

```swift
let stub = try CompiledStub<any UserRepository> {
    $0.method("find", args: [.int("id")], returns: .string)
    $0.method("search", args: [.string("query")], returns: .custom("[String]"))
    $0.getter("count", type: .int)
}
```

Use `.custom(...)` for module-qualified types the basic builder does not know:

```swift
let stub = try CompiledStub<any PaymentGateway> {
    $0.method(
        "charge",
        args: [.double("amount"), .string("currency")],
        returns: .custom("Payments.PaymentResult"),
        throws: true
    )
}
```

## Toolchain Workarounds

If compilation fails, inspect `RuntimeCompiler.lastFailure`:

```swift
do {
    _ = try CompiledStub<any MyProtocol> {
        $0.method("load", args: [.string("id")], returns: .string)
    }
} catch {
    print(RuntimeCompiler.lastFailure?.description ?? "\(error)")
}
```

Add extra search paths before creating the stub when the generated source needs
modules outside the automatically detected build products:

```swift
RuntimeCompiler.additionalImportPaths = [customModuleDirectory]
RuntimeCompiler.additionalLibraryPaths = [customLibraryDirectory]
RuntimeCompiler.additionalFrameworkPaths = [customFrameworkDirectory]
```

Clean build products after SDK mismatch errors. The runtime compiler must use
an SDK compatible with the `.swiftmodule` files it imports.

## Key Types

- ``CompiledStub`` — the stub container; compiles a conformance via `swiftc` and dlopen.
- ``DiscoveredSignature`` — describes the methods you want the compiled stub to implement.
- ``SignatureBuilder`` — DSL for building signature lists (used inside the `CompiledStub { }` closure).
