/// Attach `@Mockable` to a protocol to generate a `<Protocol>Mock` class
/// that can create `any Protocol` test doubles at runtime.
///
/// ```swift
/// @Mockable
/// protocol UserService {
///     func fetch(id: Int) -> String
///     var count: Int { get }
/// }
///
/// // Generated: UserServiceMock class with:
/// //   - recorder: StubRecorder
/// //   - stub_fetch(handler:) convenience
/// //   - stub_count(returning:) convenience
/// //   - asProtocol(cloning:) → any UserService
/// ```
@attached(peer, names: suffixed(Mock))
public macro Mockable() = #externalMacro(
    module: "TestDoublesMacros",
    type: "MockableMacro"
)
