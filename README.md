# swift-test-doubles

Runtime protocol mocking for Swift. No macros, no source generation step, and no source access required for the zero-config path.

## Quick Start

```swift
let stub = RuntimeStub<any Calculator>()
stub.when { $0.add(1, 2) }.returns(42)

let sut: any Calculator = stub()
#expect(sut.add(1, 2) == 42)
```

## Safer Setup

The classic initializers still exist, but the throwing factories are easier to debug when setup fails:

```swift
let stub = try RuntimeStub<any PaymentGateway>.make(strategy: .auto)
print(RuntimeStub<any PaymentGateway>.diagnose())
```

Typical failure causes:

- no existing conformer in the binary for the zero-config or thunk-backed path
- a runtime-compiled mock could not import the protocol's module
- a thunk-backed method shape is outside the current thunk catalog

## macOS: Compile Without a Real Conformer

On macOS, you can build a runtime-compiled mock from explicit signatures even if no real type conforms to the protocol yet:

```swift
let stub = try RuntimeStub<any PrototypeCalculator>.compiled {
    $0.method("add", args: [.int(), .int()], returns: .int)
    $0.method("describe", args: [.int()], returns: .string)
    $0.getter("precision", type: .int)
}

stub.when { $0.add(1, 2) }.returns(3)
stub.when { $0.describe(3) }.returns("3")
stub.when { $0.precision }.returns(10)
```

Pass `moduleName:` when the protocol's module cannot be inferred from the existential type.

## How It Works

[Echo](https://github.com/Azoy/Echo) reads Swift runtime metadata to enumerate a protocol's witness table requirements. `dladdr` resolves each witness table entry to its mangled symbol, and `swift_demangle` reveals the full method signature.

Two backends sit on top of that:

- `thunks`: patch a cloned witness table with prebuilt ABI thunks
- `compiled`: generate a conforming type at test time and load it with `swiftc` on macOS

`Strategy.auto` chooses the best backend available for the requested behavior.

## Support Matrix

| Capability | `thunks` | `compiled` |
| --- | --- | --- |
| Platforms | macOS, iOS | macOS only |
| Requires an existing real conformer | Yes | No when using explicit signatures |
| Zero-config signature discovery | Yes | Yes, if a real conformer exists |
| `async` requirements | No | Yes |
| `throws` requirements | Limited fallback behavior | Yes |
| Arbitrary return types | No | Yes |
| Works in source-less / binary-only integration | Often | Yes, if the module is importable |

## API Notes

### Creating stubs

```swift
let zeroConfig = RuntimeStub<any MyProtocol>()
let checked = try RuntimeStub<any MyProtocol>.make(strategy: .auto)
```

### Stubbing methods and getters

```swift
stub.when { $0.add(1, 2) }.returns(42)
stub.when { $0.name }.returns("test")
```

### Dynamic stubs

```swift
stub.when { $0.add(any(), any()) }.answers { args in
    (args[0] as! Int) + (args[1] as! Int)
}
```

### Verification

```swift
stub.verify { $0.add(1, 2) }.wasCalled()
stub.verify(called: 2) { $0.add(1, 2) }
stub.verify(never: { $0.reset() })
```

## Current Limits

- Thunk-backed mocks cover a fixed ABI catalog. In practice that means common scalar and `String`-like shapes, not arbitrary return conventions.
- Zero-config setup still needs at least one real conformer in the loaded binary so witness-table discovery has something to inspect.
- Associated types and generic requirements are not supported.
- `dladdr`-based signature discovery depends on debug-symbol availability in test builds.

## Requirements

- Swift 6.0+
- macOS 13+ / iOS 16+
