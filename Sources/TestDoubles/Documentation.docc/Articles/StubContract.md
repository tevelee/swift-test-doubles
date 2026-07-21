# Stub Contract

Understand how ``Stub`` is constructed, configured, and verified, and where its
runtime support boundary lies.

## Overview

For task-oriented examples built on this contract, see <doc:GettingStarted>.
For construction examples and requirement-order recipes, see
<doc:ConstructionGuide>.

### At a glance

| Shape | Runtime stub path | Notes |
| --- | --- | --- |
| Ordinary protocol methods, getters, setters, subscripts, inheritance, and compositions | Automatic discovery from linked conformers or resilient requirement symbols; explicit requirements otherwise | Compositions use one group per declaring protocol. |
| Effectful getters | Automatic discovery plus complete ``Stub/GetterEffect`` hints, or explicit requirements | Swift metadata omits getter throwing behavior. |
| Swift 6.3 `read` accessors | Configure and verify them like synchronous nonthrowing getters | Stub yields the configured property or subscript result with borrowed lifetime; forwarding spies and dummies remain fail-closed. |
| Static requirements, initializers, and dynamic `Self` results | Supported with the dedicated configuration builders | Use `Stub.withValue(_:)` when passing a generated metatype to code under test. |
| Bounded primary associated types | Supported for the documented direct, `Optional`, `Array`, `Set`, `Dictionary`, setter, initializer, and direct associated-error slice | See <doc:BoundAssociatedTypes> for exact supported and rejected shapes. |
| Function arguments and results | Automatic for concrete native Swift closures, C function pointers, blocks, and documented structural containers; explicit compiler-typed adapter otherwise | See <doc:FunctionValues>; top-level nonescaping, thin, declaration-level consuming or `inout`, dependent, and parameter-pack closure shapes remain fail-closed. |
| Unsupported dependent shapes, native Swift-only superclasses, and device-only execution policy | Use ``ManualStub`` or a hand-written fake | These stay fail-closed instead of guessing at ABI behavior. |

### Construction

``Stub`` supports automatic, flat explicit, and grouped explicit construction.
Automatic construction prefers linked conformer witness thunks. When a
declaring protocol has no linked conformance, it can instead use exact
per-requirement method descriptor symbols emitted for a resilient protocol.
It walks the complete inherited and composed graph, and each declaring
protocol must provide one of those sources.

When automatic discovery is unavailable, prefer ``Stub/Requirement`` factories
using `signatureOf:` protocol members. The compiler then derives the concrete
value types and effects from the declaration. A member reference supplies a
signature, not requirement identity, so entries remain positional.

Source-less factories describe ABI schemas for shapes the
member-reference forms cannot preserve, including dependent values, dynamic
`Self`, initializers, subscripts, and explicit function adapters. Their kind,
order, types, ownership, and effects must match the declaration exactly. If no
runtime source can validate a mismatch, invoking the generated value has
undefined behavior.

Flat ``Stub/Requirement`` values describe one root protocol. Their order is
base-first, depth-first, and first-seen, followed by the requirements declared
on the root. A base inherited through multiple paths appears once. Grouped
``Stub/ProtocolRequirements`` values describe compositions. Each group is keyed
by a bare `Protocol.self`, group order is irrelevant, and requirements inside a
group remain in declaration order. An inherited requirement belongs to its
original declaring protocol; a shared base is grouped once.

Explicit source-less requirement kinds, types, and method effects must exactly
match the declaration. A read-write property or subscript contributes its
getter then setter. Explicit subscript accessors use
`Stub.Requirement.subscriptGetter(indexedBy:returning:)` and
`Stub.Requirement.subscriptSetter(indexedBy:assigning:)`.
An experimental Swift 6.3 `read` property or subscript contributes one
coroutine witness and is described explicitly with the corresponding getter
factory.
Construction validates all reliably discoverable components before allocating
runtime state. Getter throwing behavior remains caller-supplied because witness
symbols do not encode it. Detectable failures are reported as ``StubError``
values.

Direct concrete function arguments and results use automatic discovery across
managed storage, effects, ownership modifiers, nested functions, and supported
actor-isolation metadata. The runtime constructs canonical function metadata
from the witness symbol and pairs compiler-emitted reabstraction thunks already
linked into the client. This does not require protocol source, annotations, or
explicit requirement chunks. The explicit `using:` overloads documented in
<doc:FunctionValues> remain the fallback for the synchronous compiler-typed
slice; their `@convention(thin)` adapter repeats the requirement signature and
appends ``Stub/Invocation``.

The bounded associated-type path uses
``Stub/Requirement/Value/associatedType(named:)`` for a direct dependent value,
``Stub/Requirement/Value/optionalAssociatedType(named:)`` or
``Stub/Requirement/Value/arrayOfAssociatedType(named:)`` or
``Stub/Requirement/Value/setOfAssociatedType(named:)`` for the supported
single-parameter containers. Compose ``Stub/Requirement/Value/optional(wrapping:)``,
``Stub/Requirement/Value/array(of:)``, ``Stub/Requirement/Value/set(of:)``, and
``Stub/Requirement/Value/dictionary(key:value:)`` for arbitrary recursive
combinations of those containers. Every resolved set element and Dictionary key
must conform to `Hashable`. ``Stub/Requirement/Value/consuming()`` marks any of
these dependent method argument values as consuming. A direct associated typed
error is named with
`Stub.Requirement.method(_:returning:throwingAssociatedTypeNamed:isAsync:)`.
``Stub/Requirement/Value/consumingAssociatedType(named:)`` remains a direct-value
convenience. `Stub.Requirement.setter(_:)` describes a dependent setter,
while
`Stub.Requirement.initializer(_:_:isFailable:isThrowing:isAsync:)`
accepts one or more dependent values using the initializer's owned convention.
The stub itself must be specialized as a constrained
existential such as `Stub<any Source<Int>>` so the runtime has concrete metadata
for every binding.

For an unbound existential, ``Stub/AssociatedTypeBinding`` and
``Stub/AssociatedTypeBinding/binding(declaredBy:named:to:)`` inject complete
concrete metadata at construction. This caller-bound mode is limited to
associated types in covariant method and getter results or as a direct typed
error. Swift exposes dependent success results at their upper bound, so fixed
values are checked against the binding when registered and handler results are
checked when invoked. The declaring protocol plus associated-type name forms
the binding identity. Associated inputs remain rejected; use a constrained
existential such as `Stub<any Source<Int>>` for the full dependent interface.

A direct dynamic `Self` result is described by
``Stub/Requirement/Value/dynamicSelf``. Record it with
``Stub/when(returningSelf:)`` and finish with
``StubSelfResultBuilder/thenReturnValue()``, `thenThrow`, or a sync/async `then`
handler. Optional `Self?` uses
``Stub/Requirement/Value/optionalDynamicSelf``,
``Stub/when(returningOptionalSelf:)``, and
``StubOptionalSelfResultBuilder`` to choose a fresh value or `nil`.
TestDoubles creates a fresh payload backed by the same
recorder and runtime resources. The builder validates the recorded return
convention, so an ordinary requirement returning the same protocol existential
continues to use `thenReturn` or `then`. The handler returns `Void` so a payload
associated with another fabricated witness graph cannot be installed
accidentally.

### Configuration and selection

`when` records one protocol invocation using matcher arguments and returns a
builder. Finish every configuration with `thenReturn` for a constant,
`thenThrow` for a fixed error, `then` for typed behavior, or `thenDoNothing` for
a `Void` requirement with no side effect. Ignoring the builder produces a
compiler warning and does not install behavior.

The setter-specific `when` overload records a direct assignment through an
`inout` existential; the assigned value is passed to a typed handler and owned
according to Swift's setter convention. A subscript setter's runtime argument
order is the assigned value followed by its borrowed indices. Matcher recording
preserves source order and aligns it with that witness order before selection
or verification.

Compound assignment and `inout` mutation execute the read-write requirement's
`_modify` coroutine. Configure its ordinary getter and direct setter rather than
capturing a compound expression. The runtime dispatches the getter, yields
metadata-backed writable storage, then dispatches the setter with the final
value. Swift unwind is non-transactional, so a value changed before a thrown
error is written back on the abort path too. Subscript indices are retained
across the yield and passed after the final value in setter ABI order.

A Swift 6.3 `read` accessor uses its one coroutine witness as a getter-shaped
recorder dispatch. Configure and verify a property or subscript with the normal
getter APIs. The runtime initializes result storage, yields a borrowed direct or
indirect value, and destroys it only when Swift resumes or aborts the borrow.
This slice is synchronous, nonthrowing, and Stub-only; forwarding and Dummy
construction fail closed.

Handlers accept arbitrary arity through Swift parameter packs. Async handlers
may suspend as part of the caller's task, preserving task-local values,
cancellation, and priority. An async handler preserves the actor or executor on
which it was formed, including a custom serial executor, and an isolated caller
resumes on its executor. Actor-isolate it or synchronize mutable captures when
the generated existential can be invoked concurrently. Synchronous handlers and
matcher predicates are `@Sendable`.

Static requirements use ``Stub/when(_:fileID:filePath:line:column:)->StubBuilder<Result>`` and are
invoked as `type(of: value).requirement(...)`. Initializers are recorded with
the `initializer:` label. Nonfailable initializers complete with
``StubInitializerBuilder/thenInitialize()``, `thenThrow`, or a typed `then`
handler.
Failable initializers choose
``StubFailableInitializerBuilder/thenInitialize()``,
``StubFailableInitializerBuilder/thenReturnNil()``, `thenThrow`, or a typed handler that
returns ``StubFailableInitializerBuilder/Outcome/initialize`` or
``StubFailableInitializerBuilder/Outcome/returnNil``. An initialized value
uses a new private payload that shares the recorder and fabricated witness
tables.

When multiple registrations match, the first registration wins, like the
first matching case of a `switch`. Register specific matchers before broad
fallbacks; an earlier registration shadows any later one it overlaps with.
Literal matching is best-effort textual matching; prefer `equal(_:)` for
meaningful equality.

### Verification

`verify` checks a recorded instance, static, or initializer invocation
immediately and defaults to the `1...` call-count range. It accepts any
`RangeExpression<Int>`: use `.exactly(2)`, `.never()`, `2...`, or `...2` when
the count expresses meaningful behavior. An ``ArgumentCaptor`` in the
verification call captures matching arguments for later assertions. A failed
count expectation is reported through IssueReporting at the caller's file,
line, and column, allowing Swift Testing or XCTest to record a normal issue
without terminating the process. Call counts are never negative, so negative
range bounds simply cannot match an observed call count.

The `verify(_:within:_:)` overload waits without polling for a
`PartialRangeFrom<Int>` lower bound. Calls wake the waiter through the recorder's
generation event; timeout and task cancellation clean up the waiter without
leaving a verification behind. A timeout reports the final observed count at
the caller's source location.

`verifyInOrder` checks that its listed calls form a relative subsequence of the
recorded call log. Every expectation matches a distinct call, while unrelated
calls may occur between matches. It is non-consuming, does not change later
count verification, and records expectations without replaying configured
handlers. Argument captors are transactional across the sequence: they commit
only after every expectation matches. Synchronous and async calls may be mixed
in the async overload. Recorded order follows the post-matcher dispatch
linearization point, where matcher captures, the call log, and a sequenced
behavior reservation are committed atomically. It is not invocation-entry or
handler-completion order.

Every successful immediate, eventual, or ordered verification marks its matched
recorded calls without consuming them. `verifyNoMoreInteractions()` reports the
remaining unverified calls in recorded order. `clearRecordedInvocations()`
clears both the call log and verification ledger while preserving configured
behavior, sequence cursors, and runtime resources.

The labeled `verifyInOrder(mutating:)` overload records mixed method, getter,
and direct-setter sequences through an `inout` value. The label keeps it
unambiguous with the source-compatible nonmutating overload. Use `verify` when
setter count is significant.

Verification reporting is distinct from failures where execution cannot
continue safely. Invoking a value-returning requirement without configured
matching behavior, throwing from a handler attached to a nonthrowing
requirement, or violating the runtime ABI contract remains fatal.

### Matcher recording placeholders

`any()`, `matching(description:where:)`, and ``ArgumentCaptor/capture()``
synthesize valid temporary values while the `when` or `verify` closure records
an invocation. TestDoubles initializes only layouts it can form safely, such as
supported scalar, tuple, enum/optional, metatype, string, array, and recursively
supported struct values.

A reference, existential, function, recursive value, or another unsupported
layout cannot be fabricated as a valid Swift value. Pass a valid value accepted
by the requirement to `any(using:)`,
`matching(using:description:where:)`, or
``ArgumentCaptor/capture(using:)``. That value exists only to make the recorded
protocol call valid; it does not participate in matching and is not captured.

A requirement result may also need a valid value while the `when` or `verify`
closure records its invocation. Use `when(returning:_:)` or
`verify(_:returning:_:)` for reference, existential, optional, and other result
layouts that cannot be synthesized safely. The supplied value is used only
during capture; it does not replace configured behavior. Synchronous and async
forms use task-local context, and an optional `nil` is distinct from not
supplying a recording result.

### Supported protocol shapes

Stub supports instance and static methods, ordinary getters, direct property
setters, protocol subscript getters and setters, and initializer requirements
on ordinary opaque and class-constrained Swift protocol existentials, including
compositions, inherited requirements, and shared diamond bases. Methods may be
synchronous, throwing, async, or async-throwing. Effectful getters require
complete ``Stub/GetterEffect`` hints or explicit requirements. Setter values may
use direct, indirect, aggregate, or reference-containing owned values, while
subscript indices are borrowed. Initializers may be nonfailable or
failable and may throw or suspend; their arguments follow Swift's owned
initializer convention. Class existentials
store the generated payload object followed by their root witness tables and
retain the same
resource lifetime as opaque existentials. Each call to the same stub reuses
that payload, while each successful initializer creates a distinct payload.
Direct and optional dynamic `Self` results also create a distinct payload backed
by the same recorder; optional handlers may instead return `nil`. This works for
methods, getters, static requirements, and ordinary untyped throwing or async
effects.
On Apple platforms, an ordinary existential may additionally constrain its
payload to an imported Objective-C class or Swift-defined `NSObject` subclass.
Construction calls the superclass's default initializer, uses that genuine
instance as the existential object, and retains the fabricated runtime graph
through an Objective-C association. Swift protocol requirements, inheritance,
compositions, and concrete-result static requirements use the fabricated
witness tables; concrete superclass members retain their real behavior.
TestDoubles deliberately does not register a process-wide
conformance. Keep the protocol existential: erasing it to `AnyObject` discards
the fabricated witness tables, and dynamically casting it back is unsupported
and may trap under optimization.

A bounded associated-type slice supports one or more concretely bound primary
associated types across the complete layout, including direct protocol
constraints on each type. Declarations may belong to inherited bases, appear
alongside inheritance, or span multiple composed roots. Direct dependent
arguments and results, dependent setters and initializer arguments, and
dependent `Optional`, `Array`, `Set`, and direct `Dictionary` key or value
occurrences are supported. Direct and
supported container method arguments may be consuming. Methods may combine
these values with `async`, untyped `throws`, and a direct associated typed error;
effectful getters must be
described explicitly. Both automatic discovery and explicit
``Stub/Requirement`` construction are supported. See
<doc:BoundAssociatedTypes> for its ABI findings and intentionally narrow limits.
An unbound existential may instead receive a complete set of caller-supplied
bindings when dependent values appear only in covariant method or getter
results. Both automatic discovery and flat explicit construction support this
mode; dependent inputs fail during construction.

Supported value shapes include integer and floating-point values, direct and
indirect aggregates, `Void`, existentials, optionals, enums, tuples, metatypes,
and strings. These source-level types share runtime calling-convention
machinery; they do not each need a dedicated stubbing API.
Automatically discovered or explicitly described typed-throwing methods support
concrete error types and direct associated error types across otherwise
supported concrete and associated result layouts, including async suspension.
Explicit requirements use `.method(..., throwing:)` for a concrete error or
`.method(..., throwingAssociatedTypeNamed:)` for a direct associated error, and
add `isAsync: true` when needed. Concrete direct values may share result
registers. Associated errors always use caller-provided indirect storage after
substituting their concrete binding, with distinct buffers across an async
continuation. A typed-throwing handler must throw only the declared error type;
TestDoubles
configuration or runtime failures cannot be transported through that restricted
error channel.

### Unsupported protocol shapes

- Automatic function values using the thin convention, unresolved associated
  types or parameter packs, top-level nonescaping arguments, declaration-level
  consuming or `inout` closure arguments, differentiable or lifetime-dependent
  metadata, or no matching linked reabstraction thunk or eligible bounded dynamic
  bridge. The dynamic bridge covers ordinary synchronous and async closures,
  including untyped and typed throws, through six formal parameters when their
  complete register layout fits. Typed-throwing closure values require macOS 15,
  iOS 18, Mac Catalyst 18, tvOS 18, or visionOS 2; isolation, sending,
  ownership-qualified, and parameter-flagged closures require exact linked
  thunks. C function pointers and block values are supported without native
  reabstraction thunks. The
  explicit adapter path remains unavailable for async requirements, initializers,
  `_modify`, `read`, dependent closure shapes, and signatures without a free
  general-purpose argument register. A
  thick closure cannot serve as that adapter because its abstraction ABI is not
  a witness ABI.
- Associated-type protocols outside the bounded slice documented in
  <doc:BoundAssociatedTypes>, including unbound associated types without
  complete caller bindings, caller-bound dependent inputs, nested dependent
  types other than `Optional`, `Array`, `Set`, and direct `Dictionary` key or
  value occurrences, broader same-type constraints, `AnyObject`-constrained
  associated types, and typed errors that wrap an associated type.
- Superclass-constrained existentials with a native Swift-only base class, a
  bound-associated-type extended layout, no usable `NSObject` default
  initializer, an initializer requirement, or a dynamic `Self` result.
  Objective-C-only protocol existentials are also unsupported.
- `read` accessors in forwarding spies or dummies, and `read` results containing
  a function or dynamic `Self`. Use a Stub with an ordinary supported result or
  a hand-written test double.
- Direct `Self` arguments.
- Async getters discovered automatically without ``Stub/GetterEffect`` hints,
  because their throwing behavior cannot be determined safely. Supply complete
  hints or describe effectful getters explicitly.
- Matcher placeholders for references, existentials, and other layouts that
  cannot be initialized safely. Use the corresponding `using:` overload with a
  valid value while recording the invocation.
- Concrete or final methods and devirtualized calls, because only protocol
  witness calls can be intercepted.

The metatype, existential metadata, and raw protocol descriptor expose identity,
layout, requirement count, and requirement flags, but not complete callable
types or effects. A resilient protocol adds exported method descriptor symbols
whose mangled names carry that missing signature. If those symbols are absent
or stripped and no linked witness is available, automatic construction fails
closed. A mismatched caller-supplied signature still violates the ABI contract
even if it cannot be diagnosed during construction.

### Runtime and platform boundary

CI-backed release support covers macOS 13+ on arm64 and x86_64, Linux on arm64
and x86_64 with Swift 6.3+, Mac Catalyst 16+ on arm64, and arm64 simulators for
iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+. Deployment targets are compiled
at their declared minimum and executed on CI's available runner or simulator
OS. macOS x86_64 coverage runs under Rosetta.

The repository includes `Scripts/validate-android.sh` to cross-build the test
targets for Android arm64 and x86_64 with the official Swift 6.3.3 Android SDK
and NDK r27d or later. Android remains outside release support until a tagged
Echo dependency exposes its ELF image-discovery implementation on Android and
that cross-build passes without patching the dependency checkout.

Physical iOS, tvOS, visionOS, and watchOS devices are unsupported because the
runtime generates executable trampoline code and CI cannot exercise device
execution policy. `ManualStub` remains available when building for those
devices. Linux CI uses the tagged Echo dependency without patching dependency
checkouts. The README installation section lists the complete supported platform
policy.

Construction rejects async requirements whose witness receiver, arguments,
and hidden result or error storage consume all available general-purpose
argument registers: six on x86_64 and eight on arm64. The trampoline keeps one
register free because it cannot safely remove spilled witness arguments before
resuming the caller continuation.

### Ownership and concurrency

Configure and verify a stub serially, keep the ``Stub`` itself on one isolation
domain, and do not overlap those operations with calls. Recorder state is
lock-protected for invocation. For a generated value whose protocol is
`Sendable`, use `stub()` to
acknowledge explicitly that configured fixed and sequenced behavior payloads,
matcher and captor state, handler captures, and recorded invocation arguments are
type-erased and are not compiler-proven `Sendable`. The no-argument forms are
deprecated when the compiler can see the `Sendable` constraint, but remain
functional for compatibility. An unconstrained generic wrapper erases that
marker constraint and therefore cannot produce the warning. Use the explicit
form whenever a generated value will cross concurrency domains, and configure
and verify outside concurrent invocation.
``ArgumentCaptor`` is conditionally `Sendable` when its captured value is
`Sendable`.

The generated existential retains its payload, recorder, fabricated witness
table, and page-backed executable veneer arena. Releasing the ``Stub`` does not
invalidate protocol values already produced from it. When the last generated
value releases its payload, TestDoubles unregisters the recorder and unmaps the
arena pages. Construction commits the small conformance-descriptor and
witness-table identity only after the complete existential is created; failed
attempts deallocate those temporary allocations. A committed identity remains
process-stable because Swift's generic-metadata caches may retain it after the
value is gone.

An existential metatype extracted with `type(of:)` does not retain the payload.
Use `Stub.withValue(_:)` to keep a generated value alive while passing its
metatype to code under test, and do not let that metatype escape the operation.
Successful initializer results receive their own payload and may outlive both
the source value and the ``Stub``.

See <doc:TrampolineArchitecture> for the implementation behind this contract.
