# Dynamic Replacement

Replace concrete Swift declarations when you control the implementation build.

## Overview

Protocol stubs only intercept calls that dispatch through a protocol witness
table. Dynamic replacement is different: it asks Swift to replace a concrete
declaration at runtime with an `@_dynamicReplacement` implementation loaded
from another image.

Use it for:

- free functions
- concrete struct or class methods
- final methods
- calls that have been devirtualized
- code that was not written against a protocol

Do not use it when a protocol stub is enough. ``ManualStub``, ``RuntimeStub``,
and ``CompiledStub`` are easier to scope to one test.

## Build Requirement

Enable the package's `DynamicReplacement` trait. The implementation module must
also be built with Swift's implicit-dynamic frontend flag:

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["DynamicReplacement"]
)
```

```sh
swiftc -Xfrontend -enable-implicit-dynamic ...
```

For SwiftPM or Xcode builds, add the equivalent unsafe Swift flag to the
implementation target that owns the declarations you want to replace.

If the dependency is a prebuilt binary that was not compiled with this flag,
dynamic replacement is not available.

## Basic Usage

Compile and load a replacement image from a test:

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

The replacement declaration must match the original declaration's parameters,
return type, generic constraints, effects, and access level requirements well
enough for Swift to accept the dynamic replacement.

## Creating A Dynamic Subject Module In Tests

Low-level tests can compile a subject module with implicit dynamic:

```swift
let subject = try DynamicReplacementCompiler.compileDynamicModule(
    moduleName: "SubjectModule",
    source: """
    public func dynamicNumber() -> Int32 { 1 }
    """
)

try DynamicReplacementCompiler.loadReplacement(
    moduleName: "SubjectModuleReplacements",
    source: """
    import SubjectModule

    @_dynamicReplacement(for: dynamicNumber())
    public func replacement_dynamicNumber() -> Int32 { 42 }
    """,
    importPaths: [subject.directory],
    libraryPaths: [subject.directory],
    linkedLibraries: ["SubjectModule"]
)
```

## Tradeoffs

- Pro: reaches concrete declarations that protocol stubs cannot see.
- Pro: uses Swift's runtime replacement mechanism instead of witness-table
  patching.
- Pro: can cover final classes, structs, free functions, and devirtualized
  calls when the implementation build permits it.
- Con: requires control over the implementation build.
- Con: replacements are process-wide after `dlopen`.
- Con: loaded replacement images are not a per-stub resource.
- Con: tests that replace the same declaration in different ways can conflict.
- Con: macOS-only in this package because it invokes the host Swift toolchain
  and loads a dynamic library.

## Tips

- Use unique replacement module names, especially for generated test sources.
- Keep replacement source small. Import the implementation module and define
  only the replacements needed by the test.
- Avoid parallel tests that load conflicting replacements for the same
  declaration.
- Prefer a dedicated test process or test target for global replacements that
  cannot safely coexist with other tests.
- Keep protocol-based dependencies on protocol stubs. Dynamic replacement is a
  fallback for code you cannot inject.

## Workarounds

- If you cannot rebuild the implementation with implicit dynamic, use
  dependency injection with ``ManualStub`` or ``RuntimeStub`` instead.
- If a replacement bleeds across tests, move those tests into a separate test
  target or disable parallel execution for that test group.
- If the replacement cannot import the implementation module, pass the correct
  `importPaths`, `libraryPaths`, and `linkedLibraries`.
- If the original declaration is generic or overloaded, start by writing the
  replacement in ordinary Swift source and compiling it normally. Once the
  spelling is accepted, move the same source into
  `DynamicReplacementCompiler.loadReplacement(...)`.

## Relationship To Protocol Stubs

Use protocol stubs when the code under test accepts a protocol dependency:

```swift
let stub = RuntimeStub<any UserService>()
let controller = Controller(service: stub())
```

Use dynamic replacement when the code under test directly calls a concrete
declaration:

```swift
// Controller calls fetchUser(id:) directly.
try DynamicReplacementCompiler.loadReplacement(...)
```
