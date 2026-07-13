# Stub

Understand construction, matching, dispatch, and the supported protocol shapes.

## Construction modes

``Stub`` has one throwing initializer and two modes selected by its arguments.

With no arguments, it discovers requirement signatures from a concrete
conformance linked into the current process:

```swift
let stub = try Stub<any UserRepository>()
```

With explicit ``Stub/Requirement`` values, it fabricates a conformance without
needing a real implementation:

```swift
let stub = try Stub<any PrototypeCalculator>(
    .method(Int.self, Int.self, returning: Int.self),
    .method(Int.self, returning: String.self),
    .getter(Int.self)
)
```

Requirements are positional and their types and effects must exactly match the
protocol declaration. Method effects must be stated with `isThrowing` and
`isAsync`.

Construction validates the protocol shape, requirement count and kind,
function-value limitations, metadata availability, and trampoline allocation
before returning. Runtime metadata does not expose enough type information to
compare an explicit requirement's supplied types or effects with the protocol;
an incorrect declaration violates the ABI contract. Failures the library can
detect are reported as ``StubError`` values.

## Configuration

`when` records one protocol invocation using its matcher arguments. Finish a
value-returning configuration with `returns` for a constant or `then` for typed
behavior. A bare `when` installs the no-op fallback for a `Void` requirement:

```swift
stub.when { $0.find(id: any()) }.returns("fallback")
stub.when { $0.find(id: equal(42)) }.then { (id: Int) in
    "user-\(id)"
}
stub.when { $0.reset() }
```

Handlers accept arbitrary arity through Swift parameter packs. Async handlers
may suspend; they execute as part of the caller's task rather than a detached
task.

If multiple registrations match, explicit equality has higher specificity than
a literal, a literal outranks a predicate, and a predicate outranks `any()` or
capture. The first registration wins a tie. Literal matching is best-effort
textual matching; prefer `equal(_:)` for meaningful equality.

## Verification

`verify` records the expected invocation and immediately checks its count:

```swift
stub.verify { $0.find(id: any()) }                 // at least once
stub.verify(.exactly(3)) { $0.find(id: any()) }
stub.verify(.never) { $0.find(id: equal(-1)) }
```

Use an ``ArgumentCaptor`` in the verification call when the arguments are part
of the assertion.

## Supported shapes

Stub supports instance methods and ordinary getters on a single,
non-class-constrained protocol without inherited or associated requirements.
Those requirements may be synchronous, throwing, async, or async-throwing. ABI
coverage includes integer and floating-point values, direct and indirect
aggregates, void, existentials, optionals, enums, tuples, metatypes, and strings.

These Swift source-level types share runtime calling-convention machinery; they
do not each need a separate stubbing API.

## Limitations

- Function and closure arguments or returns are rejected because safe protocol
  witness dispatch requires compiler-generated closure reabstraction.
- Protocol compositions are not supported.
- Read-write properties and class-constrained, inherited, associated-type,
  initializer, static, `_read`, and `_modify` requirements are rejected during
  construction.
- Explicit requirement types and effects are caller-supplied and cannot be
  checked against the protocol metadata. A mismatch violates the ABI contract.
- `any()` cannot synthesize a safe placeholder for an existential-typed
  argument; use a concrete conforming value when recording that invocation.
- On x86_64, async requirements with six integer-class arguments cross an
  unhandled continuation-register boundary. That shape is currently supported
  only on arm64.
- Only protocol witness calls can be intercepted. Concrete/final methods and
  devirtualized calls are outside the library's scope.
- Configure a stub serially before invoking it concurrently.
- Keep the owning `Stub` alive while using the fabricated protocol value.

See <doc:TrampolineArchitecture> for the runtime design.
