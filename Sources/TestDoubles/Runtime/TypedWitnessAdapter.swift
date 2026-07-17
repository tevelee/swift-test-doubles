import Echo

/// Type-erased construction of a compiler-emitted thin witness adapter.
struct TypedWitnessAdapterFactory: @unchecked Sendable {
    let functionType: Any.Type
    let invocationType: Any.Type
    let make: @Sendable (StubRecorder, MethodDescriptor) -> TypedWitnessAdapter

    func incompatibility(with method: MethodDescriptor) -> String? {
        guard let metadata = reflect(functionType) as? FunctionMetadata else {
            return "The typed adapter must be a Swift function."
        }
        guard metadata.flags.convention == .thin else {
            return "The typed adapter must use `@convention(thin)` so its argument and result ABI matches the protocol witness."
        }
        guard metadata.flags.isAsync == false else {
            return "Typed closure adapters for async requirements are not supported yet."
        }
        guard method.isAsync == false else {
            return "A synchronous typed adapter cannot implement an async requirement."
        }
        guard metadata.flags.throws == method.isThrowing else {
            return "The typed adapter's throwing effect does not match the requirement."
        }
        guard method.typedErrorUsesIndirectResultSlot == false else {
            return "Typed closure adapters do not support a caller-provided indirect typed-error buffer."
        }
        guard metadata.paramTypes.count == method.argumentTypes.count + 1 else {
            return "The typed adapter must append one Stub.Invocation parameter after the requirement's \(method.argumentTypes.count) argument(s)."
        }
        for (offset, pair) in zip(metadata.paramTypes.dropLast(), method.argumentTypes)
            .enumerated()
        {
            guard ObjectIdentifier(pair.0) == ObjectIdentifier(pair.1) else {
                return "Typed adapter argument \(offset) is \(runtimeTypeName(pair.0)), expected \(runtimeTypeName(pair.1))."
            }
        }
        guard let lastParameter = metadata.paramTypes.last,
            ObjectIdentifier(lastParameter) == ObjectIdentifier(invocationType)
        else {
            return "The typed adapter's final parameter must be \(runtimeTypeName(invocationType))."
        }
        guard ObjectIdentifier(metadata.resultType) == ObjectIdentifier(method.returnType) else {
            return "The typed adapter returns \(runtimeTypeName(metadata.resultType)), expected \(runtimeTypeName(method.returnType))."
        }
        guard invocationArgumentIndex(for: method) < generalPurposeArgumentLimit else {
            return "The requirement's explicit arguments leave no general-purpose argument register for its Stub.Invocation adapter parameter on this architecture."
        }
        return nil
    }

    func invocationArgumentIndex(for method: MethodDescriptor) -> Int {
        typedAdapterArgumentIndex(for: method)
    }

    private var generalPurposeArgumentLimit: Int {
        #if arch(x86_64)
            6
        #else
            8
        #endif
    }
}

extension FunctionMetadata.Flags {
    /// `FunctionTypeFlags::Async` in Swift's runtime ABI.
    fileprivate var isAsync: Bool { bits & 0x2000_0000 != 0 }
}

/// Retains the dispatch object explicitly appended to a thin adapter's
/// argument list for the lifetime of the fabricated witness table.
final class TypedWitnessAdapter: @unchecked Sendable {
    let target: UnsafeRawPointer
    let invocation: UnsafeRawPointer
    let invocationArgumentIndex: Int
    private let retainedInvocation: AnyObject

    init(
        target: UnsafeRawPointer,
        invocationArgumentIndex: Int,
        invocation: AnyObject
    ) {
        self.target = target
        self.invocation = UnsafeRawPointer(Unmanaged.passUnretained(invocation).toOpaque())
        self.invocationArgumentIndex = invocationArgumentIndex
        retainedInvocation = invocation
    }
}

extension Stub {
    /// Dispatch access passed to a requirement's compiler-typed witness adapter.
    ///
    /// Use ``call(_:returning:)`` from a nonthrowing adapter and
    /// ``callThrowing(_:returning:)`` from a throwing adapter. Arguments are
    /// boxed only after Swift has received them with the requirement's exact
    /// types and escaping conventions.
    public final class Invocation: @unchecked Sendable {
        private let recorder: StubRecorder
        private let method: MethodDescriptor

        fileprivate init(recorder: StubRecorder, method: MethodDescriptor) {
            self.recorder = recorder
            self.method = method
        }

        /// Records or dispatches a synchronous nonthrowing requirement.
        public func call<each Argument, Result>(
            _ arguments: repeat each Argument,
            returning resultType: Result.Type = Result.self
        ) -> Result {
            do {
                return try dispatch(repeat each arguments, returning: resultType)
            } catch {
                fatalError(
                    "[TestDoubles] A nonthrowing typed adapter for '\(method.name)' threw \(error)."
                )
            }
        }

        /// Records or dispatches a synchronous untyped-throwing requirement.
        public func callThrowing<each Argument, Result>(
            _ arguments: repeat each Argument,
            returning resultType: Result.Type = Result.self
        ) throws -> Result {
            try dispatch(repeat each arguments, returning: resultType)
        }

        /// Records or dispatches a synchronous typed-throwing requirement.
        public func call<each Argument, Result, Failure: Error>(
            _ arguments: repeat each Argument,
            returning resultType: Result.Type = Result.self,
            throwing failureType: Failure.Type
        ) throws(Failure) -> Result {
            do {
                return try dispatch(repeat each arguments, returning: resultType)
            } catch let failure as Failure {
                throw failure
            } catch {
                preconditionFailure(
                    "[TestDoubles] Typed adapter for '\(method.name)' expected \(Failure.self), got \(type(of: error))."
                )
            }
        }

        private func dispatch<each Argument, Result>(
            _ arguments: repeat each Argument,
            returning resultType: Result.Type
        ) throws -> Result {
            var erased: [Any] = []
            for argument in repeat each arguments {
                erased.append(argument)
            }

            if recorder.mode == .capturing {
                _ = try? recorder.dispatch(method: method, args: erased)
                return recordingPlaceholder(for: resultType)
            }
            let result = try recorder.dispatch(method: method, args: erased)
            guard let typed = result as? Result else {
                fatalError(
                    "[TestDoubles] Stubbed return for '\(method.name)' is not \(Result.self)."
                )
            }
            return typed
        }

        private func recordingPlaceholder<Result>(for type: Result.Type) -> Result {
            if let box = RecordingReturnPlaceholderContext.box {
                guard let value = box.value as? Result else {
                    preconditionFailure(
                        "[TestDoubles] Recording placeholder for '\(method.name)' is "
                            + "\(Swift.type(of: box.value)), expected \(type)."
                    )
                }
                return value
            }
            guard let placeholder = PlaceholderValue.make(type) else {
                preconditionFailure(
                    "[TestDoubles] Cannot synthesize a recording placeholder for \(type). "
                        + "Use the `returning:` placeholder overload of `when`/`verify` instead."
                )
            }
            return placeholder
        }
    }
}

extension Stub.Requirement {
    static func typedAdapterFactory<Adapter>(
        _ adapter: Adapter
    ) -> TypedWitnessAdapterFactory {
        var adapter = adapter
        let word = withUnsafeBytes(of: &adapter) { bytes in
            guard bytes.count >= MemoryLayout<UInt>.size else { return UInt(0) }
            return bytes.load(as: UInt.self)
        }
        return TypedWitnessAdapterFactory(
            functionType: Adapter.self,
            invocationType: Stub<P>.Invocation.self,
            make: { recorder, method in
                let invocation = Stub<P>.Invocation(recorder: recorder, method: method)
                guard let target = UnsafeRawPointer(bitPattern: word) else {
                    preconditionFailure("[TestDoubles] A typed witness adapter has no entry point.")
                }
                return TypedWitnessAdapter(
                    target: target,
                    invocationArgumentIndex: typedAdapterArgumentIndex(for: method),
                    invocation: invocation
                )
            }
        )
    }
}

private func typedAdapterArgumentIndex(for method: MethodDescriptor) -> Int {
    method.argumentLayouts.reduce(into: 0) { count, layout in
        switch layout {
            case .void, .floatingPoint:
                break
            case .integer(let words):
                count += words
            case .aggregate(let parts):
                count += parts.count { $0.register == .gp }
            case .indirect:
                count += 1
        }
    }
}
