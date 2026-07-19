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

func typedAdapterArgumentIndex(for method: MethodDescriptor) -> Int {
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
