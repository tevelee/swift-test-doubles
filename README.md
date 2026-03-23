# swift-test-doubles

Runtime protocol mocking for Swift. No macros, no source access needed.

## Quick Start

```swift
let stub = RuntimeStub<any Calculator>()
stub.when { $0.add(1, 2) }.returns(42)
let sut: any Calculator = stub()
sut.add(1, 2) // 42
```

## How It Works

[Echo](https://github.com/Azoy/Echo) reads Swift runtime metadata to enumerate a protocol's witness table requirements. `dladdr` resolves each witness table entry to its mangled symbol, and `swift_demangle` reveals the full method signature. Pre-compiled thunks (keyed by signature shape) are patched into a cloned witness table, and an existential container is assembled at runtime pointing to that table. The result is a fully functional protocol existential with no macros and no access to the protocol's source.

## API Reference

### Creating a stub

```swift
let stub = RuntimeStub<any MyProtocol>()
```

Zero-config init -- signatures auto-discovered from the binary.

### Stubbing methods and getters

```swift
stub.when { $0.add(1, 2) }.returns(42)
stub.when { $0.name }.returns("test")
```

### Stubbing setters

```swift
stub.when(setting: { $0.name = "x" }).performs()
```

### Dynamic stubs

```swift
stub.when { $0.add(any(), any()) }.answers { args in
    (args[0] as! Int) + (args[1] as! Int)
}
```

### Argument matchers

- `any()` -- matches any value
- `equal(value)` -- matches a specific `Equatable` value
- `match { $0 > 5 }` -- matches values passing a predicate

### Verification

```swift
stub.verify { $0.add(1, 2) }.wasCalled()
stub.verify { $0.add(1, 2) }.wasCalled(times: 2)
stub.verify(called: 2) { $0.add(1, 2) }
stub.verify(never: { $0.reset() })
```

### Getting the protocol existential

```swift
let sut: any MyProtocol = stub()   // callAsFunction
let sut: any MyProtocol = stub.proxy
```

## Limitations

- Requires at least one conforming type in the binary (standard when importing the module that defines the protocol).
- Pre-compiled thunks cover common signatures: `Int`, `String`, `Bool`, `Double`, `Void`, 0-3 arguments.
- No `async`/`throws` methods yet.
- No associated types or generic methods.
- `dladdr`-based signature discovery requires debug symbols (standard in test targets).
- Apple platforms only (ARM64 + x86_64).

## Requirements

- Swift 6.0+
- macOS 13+ / iOS 16+
