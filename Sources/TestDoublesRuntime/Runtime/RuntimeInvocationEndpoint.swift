/// The TestDoubles-owned semantic endpoint used by a compiler-typed witness
/// adapter. The runtime retains and transports this object opaquely; only the
/// public layer decides how a decoded typed call is recorded or dispatched.
package protocol RuntimeInvocationEndpoint: AnyObject, Sendable {
    func dispatchTyped<Result>(
        method: MethodDescriptor,
        args: [Any],
        as resultType: Result.Type
    ) throws -> Result
}
