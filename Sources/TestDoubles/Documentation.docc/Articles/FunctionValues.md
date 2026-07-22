# Function Values

Stub protocol requirements that accept or return function values, including
documented structural containers, with no protocol annotations or source access
required for automatic runtime discovery.

## Overview

### Automatic runtime support

Automatic signature discovery resolves demangled function spellings into
canonical Swift function metadata. Ordinary synchronous and async native
closures use a runtime-built arm64/x86_64 bridge, so they do not depend on closure
reabstraction symbols being present in the linked client. Extended shapes use
the paired direct-to-generic and generic-to-direct thunks that Swift emitted
when an exact match is available. Arguments cross into the recorder's `Any`
storage in the first direction; results cross back to witness ABI in the
second. Captured contexts are retained for the complete transported lifetime.

No ``Stub/Requirement`` chunks, macro annotations, generated conformers, or
access to the protocol declaration's source are involved:

```swift
typealias Transform = @Sendable (Int) -> Int

protocol Transformer {
    func transform(_ body: @escaping Transform) -> Transform
}

let identity: Transform = { $0 }
let stub = try Stub<any Transformer>()

stub.when(returning: identity) {
    $0.transform(any(using: identity))
}.then { (body: Transform) in
    let captured = body(20) + 1
    return { _ in captured }
}

let transformed = stub().transform { $0 * 2 }
// transformed(0) == 41
```

Automatic transport covers native Swift closures plus `@convention(c)` function
pointers and `@convention(block)` values. C and block values use their ordinary
value witnesses; native closures select the bounded dynamic bridge or an exact
linked reabstraction pair according to their complete metadata.

The native slice covers ordinary and `@Sendable` closures, captured and
ownership-managed values, nested escaping functions and nested nonescaping
callbacks, `throws`, typed throws with direct or indirect inner errors, `async`,
`async throws`, `inout`, `borrowing`, `consuming`, isolated, variadic, and
autoclosure parameters inside a closure type, `sending` parameters and results,
global-actor closures, `@isolated(any)`, `nonisolated(nonsending)`, and top-level
public noncopyable nominal parameters. Declaration-level borrowing and escaping
autoclosure closure parameters are also supported.

Closure values can cross synchronous, throwing, async, and async-throwing
methods, static methods, initializers, properties, and subscripts. Read-write
closure properties use the ordinary getter and setter configuration through
their `_modify` coroutine. Optional and tuple structural wrappers are
recursively reabstracted on return; arrays and nominal containers preserve
their closure payloads through their own value witnesses. Dynamic actor
isolation carried by an `@isolated(any)` value is preserved across the recorder.

The thunk-independent bridge covers ordinary and `@Sendable` synchronous and
async closures, including untyped and typed `throws`, mixed integer and
floating-point values, direct and indirect aggregates, genuine suspension, and
recursively bridgeable higher-order function parameters and results. Typed
errors may use direct GP return registers, a direct caller-owned error slot, and
a distinct generic `@error @out` slot.
Typed-throwing closure values require the standard-library runtime in macOS 15,
iOS 18, Mac Catalyst 18, tvOS 18, or visionOS 2. Construction fails closed on
earlier Apple runtimes; ordinary closures and typed-throwing protocol methods
continue to use the package's lower deployment targets.
Direct-to-generic argument transport supports zero through six formal
parameters. Generic-to-direct result transport supports up to eight parameters
on arm64 and six on x86-64. Both directions must also fit the architecture's
actual general-purpose and floating-point register budgets, including any
hidden typed-error address; the dynamic bridge does not spill closure
parameters to the stack. See <doc:ClosureReabstractionInternals> for the two
lowered function representations and their ownership rules.

Tuple and `Optional` payloads are recursively reabstracted. `Result`, arrays,
dictionaries, user enums, and public generic nominal wrappers keep their opaque
value representation while their metadata and value witnesses carry closure
payloads. Source-less generic nominal discovery accepts exported struct, enum,
and class descriptors with up to four runtime key type arguments. A constrained
generic that also needs runtime witness-table arguments fails closed.

Actor-isolated, ownership-qualified, variadic, autoclosure-parameter, and other
extended native closure shapes still require an exact compiler-emitted
reabstraction pair retained in the linked image. Ordinary
`async`, `async throws`, and async typed-throws shapes use the dynamic bridge;
extended async isolation and sending flags remain on the exact-thunk path.
Construction fails closed if neither that pair nor the bounded dynamic bridge
is available.

### Associated-dependent function values

A function value that contains a bound associated type remains unsupported,
including an escaping, synchronous, nonthrowing unary function. Its outer value
still uses Swift's fixed two-word function layout, but that layout does not
describe the inner generic calling convention.

Debug builds may retain the exact compiler-emitted partial-apply thunk needed
to cross the dependent boundary, while optimized builds may eliminate it.
Linked-symbol discovery is therefore not a durable construction-time proof.
Automatic and explicit construction reject these values before transport.
Supplying the substituted concrete function type through
``Stub/Requirement/Value`` does not erase the dependency recorded by the
protocol requirement.

Function values cannot be synthesized as recording placeholders. Use
``any(using:)``, `matching(using:description:where:)``, or
``ArgumentCaptor/capture(using:)`` for a function argument. Use
`when(returning:_:)` and `verify(_:returning:_:)` for a function result.

When a callback is the first of several arguments, use the synchronous
``StubBuilder/thenEscaping(_:)-69iax`` or asynchronous
``StubBuilder/thenEscaping(_:)-5utqd`` overload so its escaping convention is
preserved while the trailing arguments are decoded:

```swift
stub.when {
    $0.apply(any(using: identity), to: any())
}.thenEscaping { (body: Transform, value: Int) in
    body(value)
}
```

The asynchronous overload accepts an `async` or `async throws` handler when the
protocol requirement is asynchronous.

### Explicit compiler adapter

Use an explicit compiler-typed adapter when automatic symbol discovery is
unavailable but the requirement remains inside the adapter's synchronous,
concrete slice. The protocol may still come from a separate module; only its
ordinary Swift interface must be importable.

The adapter is a noncapturing `@convention(thin)` function. It repeats the
requirement's explicit parameters exactly and appends ``Stub/Invocation``:

```swift
typealias Formatter = (String) -> String
typealias FormatterStub = Stub<any FormatterService>

let adapter: @convention(thin) (
    @escaping Formatter,
    FormatterStub.Invocation
) -> Formatter = { formatter, invocation in
    invocation.call(formatter)
}

let placeholder: Formatter = { $0 }
let stub = try FormatterStub(
    .method(
        Formatter.self,
        returning: Formatter.self,
        using: adapter
    )
)
```

Swift receives the witness arguments with their exact source types before the
adapter calls the generic recorder. Construction checks the adapter convention,
argument and result types, effects, final invocation parameter, and register
capacity before allocating executable memory. Eight general-purpose argument
registers are available on arm64 and six on x86-64.

Untyped throwing adapters declare `throws` and use
``Stub/Invocation/callThrowing(_:returning:)``. A concrete typed-throws adapter
uses the `Requirement.method(...throwing:using:)` overload and calls
`Invocation.call(...returning:throwing:)` with the same error type. Concrete
typed errors must fit the direct error-result registers; an indirect typed-
error buffer remains outside this adapter slice.

### Remaining boundary

Automatic transport remains fail-closed for top-level nonescaping closure
arguments, `@convention(thin)` values, declaration-level consuming or `inout`
closure arguments, all associated-dependent closures, closure types containing
parameter packs, differentiable or lifetime-dependent function metadata, and
native shapes without an exact linked reabstraction pair or an eligible dynamic
bridge. The dynamic path specifically excludes global-actor or extended
isolation and sending flags, noncopyable values,
parameter flags, and layouts that exceed its formal-parameter or register
budgets.

Swift's public demangler erases the escaping distinction. To avoid illegally
retaining a stack closure, automatic discovery checks every raw `XE` noescape
operator against the exact mangling of one reconstructed outer function type.
This admits a noescape callback that remains scoped to an escaping outer
invocation, while any uncovered marker—including a top-level noescape
argument—still rejects the requirement.

The explicit adapter itself remains unavailable for async requirements,
initializers, `_modify`, dependent closure shapes, and signatures without a free
general-purpose argument register. A thick Swift closure is deliberately
rejected as an adapter: its abstraction ABI is not the protocol witness ABI
even when the printed source signature is identical.
