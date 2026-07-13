# Strategy Guide

Choose the smallest strategy that gives the test the behavior it needs.

## Overview

TestDoubles has four useful tools:

| Tool | Best for | Cost | Main limitation |
|---|---|---|---|
| ``ManualStub`` | Maximum portability and explicit test doubles | You write a conforming type | Boilerplate grows with protocol size |
| ``RuntimeStub`` | Fast protocol stubs without generated Swift source | Uses Swift runtime metadata and ABI trampolines | Synchronous protocol requirements only |
| ``CompiledStub`` | Full-fidelity protocol stubs on macOS | Runs `swiftc` at test startup | macOS and toolchain required |
| ``DynamicReplacementCompiler`` | Replacing concrete functions or methods | Requires an implicit-dynamic implementation build | Process-wide replacement, not scoped to one stub |

The shared stubbing API is the same for the protocol-stub strategies:

```swift
stub.when { $0.find(id: any()) }.returns("Alice")
stub.when { $0.find(id: equal(42)) }.returns("The Answer")
stub.when { try $0.read(path: any()) }.then { (path: String) throws in
    try loadFixture(path: path)
}

stub.verify { $0.find(id: any()) }.wasCalled()
stub.verify(called: 2) { $0.find(id: any()) }
```

## Selection Rules

Start here:

1. If you can write a small conforming type and portability matters, use
   ``ManualStub``.
2. If the protocol is synchronous and you want no boilerplate, use
   ``RuntimeStub``.
3. If the protocol is async, generic-heavy, or has coroutine accessors, use
   ``CompiledStub`` on macOS or ``ManualStub`` elsewhere.
4. If the code under test does not call through a protocol existential, use
   ``DynamicReplacementCompiler`` only when you control the implementation
   build.

Use a protocol-stub strategy when the system under test receives an `any P`.
Use dynamic replacement when the system under test calls a concrete declaration
directly.

```swift
// Protocol dispatch: RuntimeStub, ManualStub, or CompiledStub can help.
let service: any UserService = stub()
let controller = Controller(service: service)

// Concrete dispatch: witness-table stubbing cannot see this call.
let controller = Controller()
controller.fetchUser(id: 42)
```

## ManualStub

ManualStub is the conservative choice. You write the conformance and delegate
each requirement into `Stub<Self>`.

```swift
struct FileServiceStub: FileService, StubConformer {
    let stub: Stub<Self>

    var basePath: String { stub.basePath }
    func exists(at path: String) -> Bool { stub.exists(at: path) }
    func read(path: String) throws -> String { try stub.throwingCall(path) }
    func write(path: String, content: String) throws {
        try stub.throwingCall(path, content)
    }
}

let stub = Stub<FileServiceStub>()
stub.when { try $0.read(path: any()) }.returns("contents")

let service: any FileService = stub()
```

### Tradeoffs

- Pro: no runtime ABI dependency.
- Pro: works on every supported platform.
- Pro: best debugging experience because the stub is ordinary Swift code.
- Pro: supports async because your stub methods are Swift-authored.
- Con: every protocol requirement needs a forwarding implementation.
- Con: method names for Approach B come from `#function`; keep forwarding
  method signatures simple and explicit.

### Tips

- Use dynamic-member forwarding for labeled non-void methods and getters.
- Use `stub.call`, `stub.throwingCall`, or `stub.asyncCall` for void,
  throwing, and async requirements.
- Keep the conforming stub type close to the tests that own it. It acts as
  test documentation.

## RuntimeStub

RuntimeStub builds a protocol existential whose witness table points at one
architecture trampoline. The trampoline spills register and stack state into a
frame, then Swift code decodes arguments and encodes returns using real type
metadata and value witness tables.

There are three ways to give RuntimeStub signatures.

### Zero-Config Discovery

Use this when a real conformer is already linked into the test binary.

```swift
let stub = RuntimeStub<any UserRepository>()
```

RuntimeStub finds an existing conformance with Echo, reads the protocol
requirement slots, and discovers signatures from the witness symbols.

Tradeoff: this is the shortest call site, but it depends on a real conformer
being present and on symbol information being available enough for discovery.

Workaround: if no conformer exists, use module discovery or explicit slots.

### Module Signature Discovery

Use this when the protocol's compiled Swift module is importable but no real
conformer is linked.

```swift
let stub = try RuntimeStub<any PrototypeCalculator>.makeFromModule()
```

RuntimeStub invokes `swift symbolgraph-extract`, reads structured protocol
requirements, and maps those signatures onto protocol descriptor slots.

Tradeoff: no conformer is needed, but the host must have a Swift toolchain and
the module must be discoverable by the test process.

Workarounds:

- Pass `moduleName:` when the module cannot be inferred from `any P`.
- Make sure the test target imports the module that defines the protocol.
- Use explicit slots when symbolgraph extraction is unavailable.

### Explicit Slots

Use explicit slots when you want full control or the signature cannot be
discovered automatically.

```swift
let stub = try RuntimeStub<any Gateway>.make(
    .method(
        args: [Int.self, Money.self, String.self, Bool.self],
        returns: Receipt.self,
        throws: true
    )
)
```

Slot order is the protocol requirement order after RuntimeStub skips
non-callable witness entries such as base-protocol records, associated type
records, associated conformance records, and coroutine accessors.

Tradeoff: explicit slots are portable and avoid discovery, but you must keep
the slot list in sync with the protocol declaration.

Tips:

- Use `.getter(T.self)` for read-only properties.
- Use `.method(args:returns:throws:)` for high arity, throwing methods, and
  custom value types.
- Use `.method(A.self, B.self, returns: R.self)` for short common signatures.
- Put a comment next to every slot naming the requirement it represents.
- Use `RuntimeStub<any P>.setupScaffold()` when you do not know the slot order.

```swift
let stub = try RuntimeStub<any PrototypeCalculator>.make(
    .method(Int.self, Int.self, returns: Int.self), // add(_:_:)
    .method(Int.self, returns: String.self),        // describe(_:)
    .getter(Int.self)                               // precision
)
```

### ABI Coverage

RuntimeStub currently covers the synchronous ABI cases exercised by the test
suite:

- integer and pointer arguments in registers and on the stack
- `Float` and `Double` arguments, including mixed and stack-spilled cases
- class references
- `String`
- small integer-like values
- small direct structs, including mixed integer/floating-point fields
- large struct returns through the indirect return buffer
- throwing methods through Swift's error register
- direct aggregate returns through general-purpose and floating-point registers

Runtime marshalling depends on real Swift metadata. When metadata is known,
values are copied with value witness operations rather than raw bit retention
heuristics.

### RuntimeStub Limits

RuntimeStub intentionally rejects async requirements. Swift async witnesses use
a different calling convention with async contexts; use ``CompiledStub`` on
macOS or ``ManualStub`` elsewhere.

RuntimeStub also skips coroutine accessors such as `_read` and `_modify`.
Protocols that expose effects through those accessors should use
``CompiledStub`` or ``ManualStub``.

The fabricated conformance is used to build the existential directly. Do not
depend on unrelated runtime conformance lookup such as creating an arbitrary
payload and expecting `as? P` to discover this fabricated conformance.

The recorder is mutable test state. Avoid concurrently driving the same stub
from multiple tasks unless your test adds synchronization around the calls.

## CompiledStub

CompiledStub generates a Swift type that conforms to the protocol, compiles it
into a dylib, opens it with `dlopen`, and extracts its witness table.

```swift
let stub = try CompiledStub<any DataLoader> {
    $0.method("fetch", args: [.string("url")], returns: .string, async: true)
    $0.method("save", args: [.string("data")], returns: .bool, throws: true)
}
```

Because the generated functions are Swift-authored, Swift gives them the right
calling convention for async and throwing requirements.

### Tradeoffs

- Pro: no real conformer is required.
- Pro: better language coverage than a raw ABI trampoline.
- Pro: async requirements are supported.
- Con: macOS only.
- Con: requires a compatible Swift toolchain at test runtime.
- Con: first use per generated source pays a `swiftc` startup cost.
- Con: generated source must be able to import all referenced types.

### Toolchain Tips

CompiledStub tries to find the same `swiftc` and SDK used to build the test
module. If compilation fails, inspect `RuntimeCompiler.lastFailure`.

```swift
do {
    _ = try CompiledStub<any MyProtocol> { builder in
        builder.method("load", args: [.string("id")], returns: .string)
    }
} catch {
    print(RuntimeCompiler.lastFailure?.description ?? "\(error)")
}
```

If your protocol depends on modules outside normal build products, configure
the compiler search paths before creating the stub:

```swift
RuntimeCompiler.additionalImportPaths = [customModuleDirectory]
RuntimeCompiler.additionalLibraryPaths = [customLibraryDirectory]
RuntimeCompiler.additionalFrameworkPaths = [customFrameworkDirectory]
```

Workarounds:

- Clean build products after SDK mismatch errors.
- Prefer explicit signatures when auto-discovery cannot infer labels or types.
- Use ``ManualStub`` when running on Linux, iOS devices, or other hosts without
  a runtime compiler.

## Dynamic Replacement

Dynamic replacement is not a protocol-stub strategy. It loads an image that
contains `@_dynamicReplacement` declarations for concrete functions or methods.

The implementation module must be built with Swift's implicit-dynamic frontend
flag:

```sh
swiftc -Xfrontend -enable-implicit-dynamic ...
```

Then a test can compile and load a replacement image:

```swift
try DynamicReplacementCompiler.loadReplacement(
    moduleName: "MyFeatureReplacements",
    source: """
    import MyFeature

    @_dynamicReplacement(for: fetchUser(id:))
    public func replacement_fetchUser(id: Int) -> User {
        User(id: id, name: "stub")
    }
    """,
    importPaths: [builtProductsDirectory],
    libraryPaths: [builtProductsDirectory],
    linkedLibraries: ["MyFeature"]
)
```

### Tradeoffs

- Pro: can replace free functions, concrete methods, final methods, and calls
  that do not go through a protocol existential.
- Pro: uses Swift's runtime replacement mechanism.
- Con: requires control over the implementation build.
- Con: replacements are process-wide after the image loads.
- Con: replacement declarations must exactly match the original declarations.
- Con: currently macOS and the opt-in `DynamicReplacement` trait only.

Tips:

- Use unique replacement module names in tests to avoid symbol collisions.
- Treat replacements as test-process global state. Avoid parallel tests that
  load conflicting replacements for the same declaration.
- Keep replacement source small and explicit. Import the implementation module,
  then declare only the replacements needed by the test.
- Use `compileDynamicModule` in low-level tests that need to create a subject
  module built with implicit dynamic.

Workarounds:

- If the dependency is a prebuilt binary that was not compiled with
  implicit-dynamic, dynamic replacement is unavailable.
- If you only need protocol behavior, prefer RuntimeStub or ManualStub.
- If replacements leak across tests, split those tests into a separate test
  process or use unique test targets.

## Matching And Verification Tips

Matchers work the same across all protocol-stub strategies.

```swift
stub.when { $0.search(query: any()) }.returns([])
stub.when { $0.search(query: any(where: { $0.hasPrefix("admin") })) }
    .returns(["root"])
stub.when { $0.search(query: equal("alice")) }.returns(["Alice"])
```

The most specific matching stub wins:

| Matcher | Specificity |
|---|---|
| `equal(_:)` or a literal captured during recording | highest |
| `any(where:)` | middle |
| `any()` | lowest |

For matchers with equal specificity, the first registered matching stub wins.
Register broad defaults first and add more specific stubs afterward.

`verifyOrder` checks that the expected methods appear in order in the call log.
They do not need to be adjacent, and arguments are not part of the order check.
Verify arguments separately when they matter:

```swift
stub.verifyOrder {
    _ = $0.load(id: any())
    _ = $0.save(user: any())
}
stub.verify { $0.load(id: equal(42)) }.wasCalled()
stub.verify { $0.save(user: any(where: { $0.id == 42 })) }.wasCalled()
```

Use `_ =` inside `verifyOrder` for non-void methods to silence unused-result
warnings.

## Common Failures

### "No existing conformer was found"

Zero-config RuntimeStub needs a real conformer for signature discovery.

Workarounds:

- Use `RuntimeStub<any P>.makeFromModule()`.
- Pass explicit ``Slot`` values.
- Use ``CompiledStub`` with a signature builder.
- Link a small real conformer into the test binary.

### "Module name could not be inferred"

This usually means the protocol existential is a composition or the type name
does not include a module prefix.

Workarounds:

- Pass `moduleName:` to `makeFromModule(moduleName:)`.
- Use explicit slots.
- Use ``CompiledStub`` with explicit signatures.

### "No stub configured"

The system under test called a requirement that has no matching registration.

Workarounds:

- Stub every getter and method the system under test can call.
- Add a broad default with `any()` and override specific cases with
  `equal(_:)` or `any(where:)`.

### "Type mismatch"

The returned value does not match the protocol requirement's return type.

Workarounds:

- Check the `.returns(...)` type.
- For explicit RuntimeStub slots, check the slot return type.
- For CompiledStub, check the `SignatureBuilder.ReturnType`.

### Runtime compiler or symbolgraph cannot find modules

The runtime compiler and symbolgraph extractor need the same build products and
toolchain context as the test target.

Workarounds:

- Run from SwiftPM or Xcode so build product paths are in the environment.
- Set `RuntimeCompiler.additionalImportPaths`,
  `additionalLibraryPaths`, or `additionalFrameworkPaths`.
- Clean build products after SDK or toolchain changes.
- Use explicit RuntimeStub slots when module extraction is not available.

## Safety Notes

Keep the stub object alive for as long as anything can call the generated
existential.

```swift
let stub = RuntimeStub<any Service>()
let service = stub()
let controller = Controller(service: service)
controller.run()
stub.verify { $0.load() }.wasCalled()
```

Avoid this:

```swift
let controller = Controller(service: RuntimeStub<any Service>()())
```

The temporary stub can be released before the service is used.

For concurrent systems under test, use a fresh stub per test and avoid sharing
one stub across unrelated tasks. The recorder is designed as test-local mutable
state, not as a general concurrent logging service.
