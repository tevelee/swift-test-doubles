# Bound Primary Associated Types

Understand the bounded associated-type support, the ABI observations behind it,
and the work required to expand it safely.

## Overview

This is a supported, fail-closed slice rather than general associated-type
support. It accepts constrained existentials with one or more concretely bound
primary associated types across the complete protocol layout:

```swift
protocol Source<Element> {
    associatedtype Element: Equatable

    func load() -> Element
    func transform(_ value: Element) -> Element
}

let stub = try Stub<any Source<Int>>()
stub.when { $0.load() }.thenReturn(41)
stub.when { $0.transform(any()) }.then { $0 + 1 }
```

It also accepts a complete caller-supplied binding set for an unbound
existential when associated types occur only in covariant results or as a
direct typed error:

```swift
let stub = try Stub<any Source>(
    associatedTypes: [
        .binding(
            declaredBy: (any Source).self,
            named: "Element",
            to: Int.self
        )
    ]
)
stub.when { $0.load() }.thenReturn(41)
```

Swift exposes that unbound result at its upper bound rather than as `Int`.
TestDoubles checks fixed values against the bound runtime metadata during
registration and casts handler results back to the binding before initializing
the dependent result buffer. Associated inputs require a constrained
existential such as `any Source<Int>` and remain rejected in caller-bound mode.

Automatic construction needs a linked conformer or resilient requirement
symbols so it can discover callable signatures. Explicit construction names
dependent values separately from ordinary concrete values:

```swift
typealias SourceStub = Stub<any Source<Int>>
let element = SourceStub.Requirement.Value
    .associatedType(named: "Element")
let optionalElement = SourceStub.Requirement.Value
    .optionalAssociatedType(named: "Element")
let elements = SourceStub.Requirement.Value
    .arrayOfAssociatedType(named: "Element")
let elementSet = SourceStub.Requirement.Value
    .setOfAssociatedType(named: "Element")
let elementsByName = SourceStub.Requirement.Value.dictionary(
    key: String.self,
    valueAssociatedTypeNamed: "Element"
)
let optionalElementArrays = SourceStub.Requirement.Value.optional(
    wrapping: .array(of: element)
)
let elementsByOptionalSet = SourceStub.Requirement.Value.dictionary(
    key: .optional(wrapping: .set(of: .optional(wrapping: element))),
    value: .array(of: .optional(wrapping: element))
)
let elementResult = SourceStub.Requirement.Value.result(
    success: .array(of: element),
    failure: .concrete(Never.self)
)
let consumedElements = elements.consuming()

let stub = try SourceStub(
    .method(returning: element),
    .method(element, returning: element)
)
```

Automatic discovery also recognizes a bounded generic-class shape. The class
must be a linked, public, top-level Swift class with one or two unconstrained
type parameters, and every argument must resolve recursively from concrete or
associated metadata:

```swift
public final class Page<Value> {}

protocol PageSource<Element> {
    associatedtype Element
    func load() -> Page<Element>
}

let stub = try Stub<any PageSource<Int>>()
```

There is no source-less explicit `Value` schema for a generic class. Swift does
not expose an unbound generic class metatype that could identify `Page` without
either a string name or an arbitrary placeholder specialization. Both would
make the schema less precise than automatic descriptor discovery. When a linked
signature is available, describing `Page<Element>` as
`.concrete(Page<Int>.self)` is rejected because it erases the dependent source
shape.

Initializer parameters use Swift's owned initializer convention. Describe a
dependent initializer by passing one or more `Value`s:

```swift
let stub = try SourceStub(
    .initializer(element),
    .method(returning: element)
)
```

Each string is checked against the declaring protocol descriptor's
associated-type names, and concrete metadata still comes from
`any Source<Int>`. Marking `Int.self` as an ordinary concrete value would select
a different calling convention even though both source-level values are spelled
`Int` after substitution.

### ABI findings

A constrained existential such as `any Source<Int>` uses extended existential
metadata rather than ordinary existential metadata. In the tested Swift 6.3
through 6.4 runtimes, its metadata supplies a shape plus an ordered vector of
concrete primary-associated-type metadata arguments. An opaque container has a
three-word value buffer, dynamic `Self` metadata, and one witness-table pointer
per root protocol. A class-constrained container instead has one retained object
reference followed by one witness-table pointer per root. Both representations
retain the concrete bindings in type metadata; the class optimization omits
parameter metadata only from the value container.

An ordinary `any Source` existential contains its protocol descriptor and
witness-table count but no concrete associated metadata. Caller-bound
construction supplies that missing mapping explicitly, keyed by declaring
protocol descriptor and associated-type name, and validates it against every
associated accessor in the flattened layout before fabrication.

Associated-type substitution does not specialize a dependent witness method to
the concrete type's ordinary ABI. A direct `Element` argument is passed
indirectly, and a direct `Element` result uses an indirect result buffer. An
`Element?` value is also indirect, while `[Element]`, `Set<Element>`, and
`Dictionary<String, Element>` retain their collection's direct reference
layout. This rule composes recursively. `Element??` remains indirect, but
`[Element]?`, `[Element?]`, and `[String: [Element?]]` are fixed because the
nearest opaque occurrence is enclosed by a reference-backed collection shell.
`Result` considers both payloads: its formal witness transport is indirect when
either its success or failure dependency remains opaque, and uses ordinary
concrete enum classification only when both payloads have fixed transport.
Consequently, `Result<Element, ConcreteFailure>` and
`Result<[Int], Failure>` are indirect, while
`Result<[Element], ConcreteFailure>` is fixed. The rule composes through both
payloads and the surrounding supported containers.
Likewise, a reconstructed generic class is definitively reference metadata, so
`Page<Element>` remains a direct one-word reference regardless of the payload's
formal opacity. `Page<Element>?` is also one word, and wrapping the class in an
Array, Set, or Dictionary retains that container's fixed reference-backed
transport.
Dependency and ABI layout are therefore tracked separately: `[Int]` and
`[Element]` have the same physical layout but are different explicit signature
contracts. Dictionary dependencies additionally preserve the complete key and
value source shapes, and Result dependencies preserve the success and failure
source shapes.

The fabricated witness table also needs its structural entries. TestDoubles
flattens the inheritance and composition graph, then maps every metadata
argument to the protocol descriptor and associated-type name encoded by its
same-type requirement. It installs each concrete metadata value and, for a
constraint such as `Element: Equatable`, the concrete conformance witness
returned by the Swift runtime.

A descriptor's requirement signature does not separate "inherits protocol Q"
from "an associated type conforms to Q" by list order or position; both are
plain protocol-conformance requirements. Telling them apart requires parsing
the constrained subject. Self is the protocol's depth-0 index-0 generic
parameter; an associated conformance subject is a symbolic dependent-member
reference that carries both its declaring protocol descriptor and name. The
same identity is used to install the conformance in the correct structural
witness slot.

These observations rely on Swift runtime metadata and witness-table internals.
The parser checks the exact shape it understands and rejects everything else;
it must evolve alongside the repository's Swift runtime support matrix.

### Supported slice

- One or more associated-type declarations, each with exactly one concrete
  primary-associated-type binding in the existential type.
- Opaque or class-constrained existential storage, including `Sendable`
  class-bound protocols and concurrent calls after serial configuration when
  configured values, matcher or captor state, and captures are safe to share.
- Associated types declared by inherited bases or directly alongside inherited
  protocols on the same descriptor.
- Compositions containing multiple associated-type and ordinary protocols,
  with one fabricated root witness table per component.
- Direct runtime protocol constraints on associated types, such as
  `Element: Equatable`.
- Direct associated-type method arguments and results, including consuming
  direct arguments.
- Direct associated-type property getters, Swift 6.3 `read` accessors, Swift
  6.4 `yielding borrow` accessors through their supported witness, and setters.
- Arbitrarily recursive combinations of `Optional`, `Array`, `Set`,
  `Dictionary`, and `Result` containing associated and concrete leaves, in
  method arguments, results, and getter results. Every resolved `Set` element
  and `Dictionary` key must prove `Hashable`, and every resolved `Result`
  failure must prove `Error`. Method arguments in all supported container forms
  may be consuming.
- Automatically discovered linked, public, top-level generic Swift classes
  with one or two unconstrained type parameters. Every argument may recursively
  contain concrete types, associated types, and supported standard-library or
  generic-class shapes. Reconstructed metadata must identify the exact linked
  class descriptor and prove class reference metadata before construction
  proceeds.
- Direct and supported-container associated-type initializer arguments. Swift's
  initializer witness convention owns every parameter.
- Requirements with any combination of `async` and ordinary untyped `throws`.
  A direct dependent frame is already indirect, so a thrown failure uses the
  ordinary Swift `Error` register convention unchanged, and an async dependent
  result reuses the async indirect-result slot. Effectful dependent getters
  must be described explicitly because witness symbols never encode getter
  throwing.
- Direct associated typed errors are supported in synchronous and async methods.
  Their substituted concrete metadata always drives an indirect error-result
  slot, even when that concrete type would ordinarily fit in registers.
- Automatic discovery also supports an associated-dependent typed error whose
  outer type is a linked, public, top-level generic class with one or two
  unconstrained type parameters. Direct associated arguments and recursively
  nested class applications are supported. Exact descriptor-based metadata
  reconstruction proves the class reference layout before construction, so
  synchronous and async failures use the direct typed-error channel.
- Automatic discovery and explicit requirement descriptions.
- Complete caller-supplied bindings for unbound associated types used only in
  covariant method or getter results or as a direct typed error. Both flat and
  recursively nested supported-container requirements are supported; result
  values remain statically erased to their upper bounds at the call site.

The implementation has tests that pass fabricated existentials to generic code,
use multiple associated-type conformances, bind stubs to different concrete
types than their discovery conformers, exercise inherited and composed witness
graphs, and invoke a class-bound `Sendable` shape concurrently.

The generated `Sendable` existential crosses concurrency domains only in test
setups whose configured fixed and sequenced behavior payloads, matcher or captor
state, and handler captures are themselves safe to share. Keep configuration and
verification on one isolation domain.

### Rejected shapes

Automatic construction rejects the following, and explicit construction rejects
them whenever a linked conformance or resilient requirement symbol makes
signature validation possible:

- An unbound existential such as `any Source` without a complete caller-supplied
  binding set.
- Caller-bound associated types used in method arguments, setters, or other
  non-covariant positions.
- A missing, duplicate, or unknown concrete binding for any associated-type
  declaration in the flattened layout.
- Dependent values outside recursive `Optional`, `Array`, `Set`, `Dictionary`,
  `Result`, and the bounded automatic generic-class slice, such as tuples,
  generic structs or enums, metatypes, existentials, or function types
  containing `Element`.
- Generic classes with constraints, more than two type parameters, nested or
  unlinked constructors, constructors whose metadata accessor needs non-type
  arguments, and source-less explicit generic-class schemas.
- Associated-dependent typed errors whose outer shape is `Optional` or another
  value wrapper, a generic struct or enum, a constrained or unlinked class, or
  a class with more than two type parameters. Explicit concrete and string-named
  associated-error schemas cannot describe the supported generic-class source
  dependency and are rejected when linked validation is available.
- Same-type constraints other than concrete primary bindings, superclass
  constraints, `AnyObject`-constrained associated types, and other generic
  constraints outside the directly witnessed protocol-conformance form.
- Function values involving an associated type.

Borrowed and consuming direct or optional arguments use the supported indirect
call-frame shape; arrays, sets, and dictionaries keep their one-word direct
representation.
Per-argument ownership ensures the trampoline destroys only owned input storage
after first copying it into recorder-owned type erasure. Noncopyable and
nonescapable dependent values remain outside the boundary.

As with ordinary explicit requirements, protocol metadata alone does not expose
callable signature types or ownership. Resilient requirement symbols can carry
that signature, but when neither they nor a conformer are available the explicit
declaration is a trusted ABI contract: it enables the supported shapes
demonstrated above, but cannot make another nested or otherwise unsupported
source declaration safe. Do not use explicit values to force one of these
rejected declarations through construction.

### Work required for broader support

The recursive classifier is deliberately bounded to standard-library
`Optional`, `Array`, `Set`, `Dictionary`, and `Result`. Supporting other
dependent values requires formal lowering evidence for tuples, generic structs
and enums, metatypes, existentials, and function types. The implemented
containers model their distinct lowering instead of inferring a universal
convention from substituted concrete metadata. `Result` is special-cased as a
two-payload enum: either formally opaque payload makes the complete value
indirect, while two fixed payloads permit ordinary concrete enum
classification. Generic classes are accepted only after exact descriptor-based
metadata reconstruction proves reference identity and layout.

Expanding generic-class support to explicit source-less schemas needs a durable
way to identify an unapplied constructor. A string is tied to symbol spelling,
while a specialization such as `Page<Int>.self` does not state that `Int` is a
placeholder to be replaced. Until Swift can express that constructor directly,
the explicit path continues to fail closed rather than publish either contract.

Consuming `Optional`, `Array`, `Set`, `Dictionary`, and `Result` values reuse the
implemented value-witness and per-argument ownership path. Other nested,
noncopyable, and nonescapable associated types still require additional
lowering and lifetime models. An `AnyObject` associated-type constraint is also
a separate dependent reference ABI; recognizing its metadata is not enough to
transport its values safely, so construction rejects it explicitly.

Typed throws is a separate ABI case. Concrete typed errors share direct result
registers or use the caller's indirect typed-error slot as required. A direct
associated error substitutes its binding metadata and always uses the indirect
slot so the generic witness convention remains stable. Swift 6.3 and 6.4 lower
`BoxError<Element>` differently: once the exact outer generic class descriptor
is reconstructed, its reference layout fixes the formal error transport and no
opaque error slot is needed. The same rule holds for proven one- and
two-parameter class errors and recursively nested class applications.

Optional and other value wrappers, generic structs or enums, and unsupported
generic classes remain fail-closed. Supporting `Result` as an ordinary argument
or result does not widen that typed-error boundary.

The implemented multiple-binding path maps every constrained-existential
metadata argument to its same-type relationship and declaring protocol's
structural witness entries. Broader same-type relationships, layout constraints,
and conditional associated conformances still need explicit resolution rather
than inference from ordering.

Direct concrete function values use the automatic runtime slice or explicit
compiler adapter described in <doc:FunctionValues>. A closure containing
`Element` is different: it has a dependent generic lowered signature even when
its substituted surface type looks concrete. The closure's fixed two-word outer
layout does not describe that inner calling convention.

A debug build may retain the exact compiler-emitted partial-apply thunk needed
to cross that boundary, but optimized builds may eliminate it. Linked-symbol
discovery therefore cannot provide a durable construction-time proof.
Automatic and explicit construction both reject associated-dependent function
values before transport rather than treating their concrete surface types as
ABI-complete schemas.

Broader support needs stable runtime generation of the required reabstraction
or a compiler contract that guarantees the thunk remains available.
