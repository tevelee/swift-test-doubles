# Construction Guide

Choose automatic discovery, getter-effect hints, or explicit requirement
descriptions for the protocol shape under test.

## Overview

Use the zero-argument ``Stub`` initializer when the test process links a real
conformance or the protocol exports resilient requirement descriptors. Use
getter-effect hints when automatic discovery has enough metadata except for a
getter's throwing convention. Use explicit requirements when neither runtime
signature source is available, or when the test needs to describe an
effectful getter precisely.

For the complete support boundary, see <doc:StubContract>. For bounded
associated-type signatures, see <doc:BoundAssociatedTypes>.

### Automatic discovery

The zero-argument initializer first discovers requirement signatures from
conformers linked into the test process:

```swift
let stub = try Stub<any UserRepository>()
```

It can also construct a protocol with no implementation when that protocol was
compiled with library evolution and its per-requirement method descriptor
symbols are present. The metatype and existential records expose the protocol
descriptor, but do not contain callable types themselves. TestDoubles resolves
an exact symbol at each requirement record and demangles that symbol to recover
the signature.

Inherited protocols and compositions are supported. Every declaring protocol
must provide one of these sources; linked witness thunks and resilient
requirement descriptors may be mixed across the graph:

```swift
let combined = try Stub<any UserRepository & NotificationService>()
```

Ordinary class-constrained Swift protocols use the same construction API. On
Apple platforms, an ordinary existential may also combine Swift protocols with
an `NSObject`-backed superclass:

```swift
let classOnly = try Stub<any ClassOnlyRepository>()
let objectBacked = try Stub<any NSObject & LifecycleReporting>(
    .method(returning: Int.self)
)
```

Class existentials retain the generated payload directly, so values produced by
`stub()` remain valid after the ``Stub`` instance is released. Repeated calls
reuse that payload. The conformance is intentionally not registered
process-wide. Keep the protocol existential: erasing it to `AnyObject` discards
the fabricated witness tables, and dynamically casting it back is unsupported
and may trap under optimization.

For a superclass constraint, construction creates a genuine superclass instance
through `init()` and attaches the stub's runtime resources to it. This supports
imported Objective-C classes and Swift-defined `NSObject` subclasses whose
default initializer is usable; real superclass members keep their normal
implementation. Native Swift-only superclasses, Objective-C-only protocols, and
special runtime protocols remain rejected.

### Getter effect hints

Swift protocol metadata records whether a getter is `async`, but not whether
it throws. When a conformer is linked, keep automatic signature discovery and
supply only the missing throwing classification:

```swift
let stub = try Stub<any CachedProfile>(
    getterEffects: .nonthrowing, // var cachedName: String { get }
    .throwing                    // var freshName: String { get async throws }
)
```

Supply one ``Stub/GetterEffect`` for every getter in base-first, depth-first
declaration order. Methods, initializers, and setters do not consume a hint.
For inheritance or a composition, declaration-scoped groups remove ordering
ambiguity:

```swift
let stub = try Stub<any CachedProfile & NetworkProfile>(
    getterEffectsByProtocol: .effects(
        declaredBy: CachedProfile.self,
        .nonthrowing
    ),
    .effects(
        declaredBy: NetworkProfile.self,
        .throwing
    )
)
```

Hints classify ordinary untyped `throws`; they do not describe typed throws.
Use explicit requirements when no automatic signature source is available.

### Explicit requirements

If no conformer is linked and resilient requirement symbols are unavailable,
start with protocol member references. For requirements containing only
independent concrete values, the compiler derives their types and effects from
the declaration:

```swift
let stub = try Stub<any PrototypeCalculator>(
    .method(signatureOf: PrototypeCalculator.add),
    .method(signatureOf: PrototypeCalculator.describe),
    .getter(signatureOf: \PrototypeCalculator.precision),
    .setter(signatureOf: \PrototypeCalculator.precision)
)
```

Use an accessor closure when a getter is throwing or asynchronous, for example
`.getter(signatureOf: { try await $0.currentValue })`. The reference supplies a
signature, not requirement identity: entries remain positional and must stay in
protocol declaration order. Function conversion erases associated-type and
dynamic-`Self` semantics, so `signatureOf:` construction rejects those
existentials; use explicit ``Stub/Requirement/Value`` descriptions instead.
Method-reference convenience overloads accept up to six arguments because
Swift 6.3 cannot reabstract unbound method references through a parameter pack.
Use `Stub.Requirement.method(_:returning:isThrowing:isAsync:)` for a
higher-arity requirement.

Source-less factories are ABI schemas without a referenced declaration. Use them only
when a member reference cannot preserve the required ABI information, such as
associated-type values, dynamic `Self`, initializers, subscripts, function
adapters, or methods above the supported reference arity. If their kind, order,
value types, ownership, or effects differ from the declaration and no runtime
signature source is available to validate them, invoking the generated value
has undefined behavior.

For one root protocol, source-less requirements use a flat base-first,
depth-first order: each inherited protocol appears at its first occurrence,
followed by the requirements declared by the root. A shared diamond base
appears once.

```swift
let stub = try Stub<any PrototypeCalculator>(
    .method(Int.self, Int.self, returning: Int.self),
    .method(Int.self, returning: String.self),
    .getter(Int.self)
)
```

Read-write properties contribute their getter followed by their setter:

```swift
let profile = try Stub<any MutableProfile>(
    .getter(String.self),
    .setter(String.self)
)
```

For a composition, group requirements by the bare protocol that originally
declares them. Group order is irrelevant; order inside each group follows that
protocol's declaration. Supply a shared inherited protocol once:

```swift
let store = try Stub<any ExplicitReader & ExplicitWriter>(
    requirementsByProtocol: .requirements(
        declaredBy: ExplicitWriter.self,
        .method(Int.self, String.self, returning: Void.self)
    ),
    .requirements(
        declaredBy: ExplicitReader.self,
        .method(Int.self, returning: String.self)
    )
)
```

Effects are part of an explicit requirement:

```swift
let stub = try Stub<any AsyncDataLoader>(
    .method(
        String.self,
        returning: String.self,
        isThrowing: true,
        isAsync: true
    ),
    .method([String].self, returning: Void.self, isAsync: true),
    .getter(Int.self)
)
```

Name a concrete typed error with `throwing:`. Add `isAsync: true` for an async
method. This also works when no real conformer is linked:

```swift
let stub = try Stub<any AsyncTypedDataLoader>(
    .method(
        String.self,
        returning: Data.self,
        throwing: LoadError.self,
        isAsync: true
    )
)
```

Typed-throwing handlers must throw only the declared concrete error type. A
configuration or runtime failure from TestDoubles cannot be transported through
that restricted error channel.

### Static and initializer requirements

Instance and static requirements share `when` and `verify`. Swift cannot spell
the opened existential metatype as the closure parameter, so invoke a static
requirement through `type(of:)`:

```swift
stub.when { type(of: $0).defaultName() }.thenReturn("Guest")

let value: any UserFactory = stub()
#expect(type(of: value).defaultName() == "Guest")
```

Record initializers through the labeled `when(initializer:)` overload.
They return another generated value backed by the same recorder and runtime
graph. Finish a nonfailable initializer with `thenInitialize()`; failable
initializers can instead return `nil`:

```swift
stub.when(initializer: {
    type(of: $0).init(id: any())
}).thenInitialize()

stub.when(initializer: {
    type(of: $0).init(validating: any())
}).then { id in
    id > 0 ? .initialize : .returnNil
}
```

Initializer handlers may be synchronous or async and may throw when the
requirement throws. Use `Stub.withValue(_:)` when passing a generated metatype
into code under test; it keeps the witness tables and executable trampolines
alive for the operation:

```swift
try await stub.withValue { value in
    try await service.run(factory: type(of: value))
}
```

The metatype must not escape the `withValue` operation. Unlike a generated
protocol value, a Swift metatype has no ownership hook with which to retain the
stub's runtime allocations.

### Dynamic Self results

A method, getter, or static requirement that returns nonoptional `Self` can
produce a fresh value backed by the same recorder and runtime graph:

```swift
let stub = try Stub<any Duplicating>()
stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
stub.when { $0.marker() }.thenReturn(42)

let duplicate = stub().duplicate()
#expect(duplicate.marker() == 42)
```

Use `thenThrow` for a fixed error or a `Void`-returning `then` handler when
arguments, suspension, or a computed throwing failure matter. TestDoubles
creates the generated result after the handler returns, preventing a value from
a different fabricated witness graph from being returned accidentally.

Without a linked conformer or resilient requirement symbol, describe the result
as `.method(returning: .dynamicSelf)`. Optional `Self?` uses
`.optionalDynamicSelf` with `when(returningOptionalSelf:)`, which can return a
fresh generated value or `nil`. Direct `Self` inputs remain unsupported.

### Construction failures

The recoverable ``Stub``, ``Dummy``, and ``Spy`` constructors declare
`throws(StubError)` when the protocol or a requirement shape cannot be
supported. Automatic discovery resolves concrete runtime metadata for every
argument and result before allocating a witness table. When a linked
conformance is available, explicit construction also validates every signature
component that can be discovered reliably. Getter throwing behavior remains
caller-supplied. The fail-fast `makeStub`, `makeDummy`, and `makeSpy` factories
terminate with the same actionable diagnostic. No construction path launches
external tools.
