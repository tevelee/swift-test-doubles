/// The collision-free dynamic-member route returned by
/// ``ManualStub/requirements``.
@dynamicMemberLookup
public struct ManualRequirementRoute<T: ManualStubConformer> {
    let stub: ManualStub<T>

    /// Method access such as `stub.requirements.fetch(id: id)`.
    @_documentation(visibility: internal)
    public subscript(dynamicMember member: String) -> ManualMethodProxy<T> {
        ManualMethodProxy(stub: stub, name: member)
    }

    /// Property access such as `stub.requirements.count`.
    @_disfavoredOverload
    public subscript<R>(dynamicMember member: String) -> R {
        get {
            let method = stub.recorder.internManualMethod(
                signature: member,
                kind: .getter,
                returnType: R.self,
                isAsync: false,
                isThrowing: false
            )
            return stub.dispatchValue(method: method, args: [])
        }
        nonmutating set {
            let method = stub.recorder.internManualMethod(
                signature: "\(member)=",
                kind: .setter,
                returnType: Void.self,
                isAsync: false,
                isThrowing: false
            )
            let _: Void = stub.dispatchValue(method: method, args: [newValue])
        }
    }
}

/// A dynamic-call proxy used by manual requirement forwarding.
@dynamicCallable
@_documentation(visibility: internal)
public struct ManualMethodProxy<T: ManualStubConformer> {
    let stub: ManualStub<T>
    let name: String

    /// Sync, non-void: `stub.requirements.fetch(id: id)`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) -> R {
        stub.dispatchMethod(key: manualStubSignature(name, args), args: args.map(\.value))
    }

    /// Sync, void: `stub.requirements.reset()`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) {
        let _: Void = stub.dispatchMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async, non-void: `await stub.requirements.load()`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) async -> R {
        await stub.dispatchAsyncMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async, void: `await stub.requirements.refresh()`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) async {
        let _: Void = await stub.dispatchAsyncMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }
}

/// The collision-free dynamic-member route returned by
/// ``ManualStub/throwingRequirements``.
@dynamicMemberLookup
public struct ManualThrowingRequirementRoute<T: ManualStubConformer> {
    let stub: ManualStub<T>

    /// Method access: `try stub.throwingRequirements.save(item: item)`.
    @_documentation(visibility: internal)
    public subscript(dynamicMember member: String) -> ManualThrowingMethodProxy<T> {
        ManualThrowingMethodProxy(stub: stub, name: member)
    }

    /// Throwing getter access: `try stub.throwingRequirements.token`.
    /// Disfavored so Swift prefers throwing method forwarding at call sites.
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

/// Compatibility name for ``ManualThrowingRequirementRoute``.
@available(*, deprecated, renamed: "ManualThrowingRequirementRoute")
public typealias ManualThrowingRoute<T: ManualStubConformer> =
    ManualThrowingRequirementRoute<T>

/// A dynamic-call proxy used by throwing manual requirement forwarding.
@dynamicCallable
@_documentation(visibility: internal)
public struct ManualThrowingMethodProxy<T: ManualStubConformer> {
    let stub: ManualStub<T>
    let name: String

    /// Sync-throwing, non-void:
    /// `try stub.throwingRequirements.save(item: item)`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) throws -> R {
        try stub.dispatchThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Sync-throwing, void: `try stub.throwingRequirements.save(item)`.
    public func dynamicallyCall(withKeywordArguments args: KeyValuePairs<String, Any>) throws {
        let _: Void = try stub.dispatchThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async-throwing, non-void:
    /// `try await stub.throwingRequirements.refresh()`.
    public func dynamicallyCall<R>(withKeywordArguments args: KeyValuePairs<String, Any>) async throws -> R {
        try await stub.dispatchAsyncThrowingMethod(
            key: manualStubSignature(name, args),
            args: args.map(\.value)
        )
    }

    /// Async-throwing, void:
    /// `try await stub.throwingRequirements.refresh()`.
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
