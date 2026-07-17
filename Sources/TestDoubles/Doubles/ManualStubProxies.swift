/// A dynamic-call proxy returned by ``ManualStub``'s base dynamic-member
/// subscript.
///
/// Use it only from forwarding implementations on a ``StubConformer``. It
/// routes non-throwing method calls, synchronous or asynchronous, including
/// `Void` methods.
@dynamicCallable
public struct ManualMethodProxy<T: StubConformer> {
    let stub: ManualStub<T>
    let name: String

    /// Sync, non-void: `stub.fetch(id: id)`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) -> R {
        stub.dispatchMethod(key: manualStubSignature(name, args), args: args.map(\.value))
    }

    /// Sync, void: `stub.reset()`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) {
        let _: Void = stub.dispatchMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async, non-void: `await stub.load()`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) async -> R {
        await stub.dispatchAsyncMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async, void: `await stub.refresh()`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) async {
        let _: Void = await stub.dispatchAsyncMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }
}

/// Returned by ``ManualStub/throwing``. Routes sync-throwing and
/// async-throwing methods, and throwing getters.
@dynamicMemberLookup
public struct ManualThrowingRoute<T: StubConformer> {
    let stub: ManualStub<T>

    /// Method access: `try stub.throwing.save(item: item)`.
    public subscript(dynamicMember member: String) -> ManualThrowingMethodProxy<T> {
        ManualThrowingMethodProxy(stub: stub, name: member)
    }

    /// Throwing getter access: `try stub.throwing.token`.
    /// Disfavored so Swift prefers ``ManualThrowingMethodProxy`` at call sites.
    @_disfavoredOverload
    public subscript<R>(dynamicMember member: String) -> R {
        get throws {
            let method = stub.recorder.internManualMethod(
                signature: member,
                kind: .getter,
                returnType: R.self,
                isAsync: false,
                isThrowing: true
            )
            return try stub.dispatchThrowingValue(method: method, args: [])
        }
    }
}

/// A dynamic-call proxy returned by ``ManualThrowingRoute``'s dynamic-member
/// subscript.
///
/// Use it only from throwing forwarding implementations on a
/// ``StubConformer``.
@dynamicCallable
public struct ManualThrowingMethodProxy<T: StubConformer> {
    let stub: ManualStub<T>
    let name: String

    /// Sync-throwing, non-void: `try stub.throwing.save(item: item)`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) throws -> R {
        try stub.dispatchThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Sync-throwing, void: `try stub.throwing.save(item)`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) throws {
        let _: Void = try stub.dispatchThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async-throwing, non-void: `try await stub.throwing.refresh()`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) async throws -> R {
        try await stub.dispatchAsyncThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async-throwing, void: `try await stub.throwing.refresh()`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) async throws {
        let _: Void = try await stub.dispatchAsyncThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }
}

/// Composes a `#function`-style signature (`"save(item:)"`, `"add(_:_:)"`,
/// `"reset()"`) from a dynamic-member base name and its call-site argument
/// labels. This does two things: it keeps two requirements that share a base
/// name but differ in labels (Swift overloads) from colliding on the same
/// interned key, and it produces the exact same key `#function` would at an
/// equivalent call site, so the sugar route and the explicit
/// `function: String = #function` fallback intern to the same entry for the
/// same requirement.
func manualStubSignature(_ name: String, _ args: KeyValuePairs<String, Any>) -> String {
    let labels = args.map { $0.key.isEmpty ? "_" : $0.key }
    return "\(name)(\(labels.map { "\($0):" }.joined()))"
}
