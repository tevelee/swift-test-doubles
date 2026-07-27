import EchoRuntimeReflection
import InternalRuntimeContract

/// Type-erased construction of a compiler-emitted thin witness adapter.
package struct TypedWitnessAdapterFactory: @unchecked Sendable {
    package let functionType: Any.Type
    package let invocationType: Any.Type
    package let make:
        @Sendable (
            any RuntimeInvocationEndpoint,
            Int
        ) -> TypedWitnessAdapter

    package init(
        functionType: Any.Type,
        invocationType: Any.Type,
        make:
            @escaping @Sendable (
                any RuntimeInvocationEndpoint,
                Int
            ) -> TypedWitnessAdapter
    ) {
        self.functionType = functionType
        self.invocationType = invocationType
        self.make = make
    }

    package func incompatibility(with method: MethodDescriptor) -> String? {
        guard let function = FunctionTypeInfo(reflecting: functionType) else {
            return "The typed adapter must be a Swift function."
        }
        guard function.convention == .thin else {
            return "The typed adapter must use `@convention(thin)` so its argument and result ABI matches the protocol witness."
        }
        guard function.effects.isAsync == false else {
            return "Typed closure adapters for async requirements are not supported yet."
        }
        guard method.isAsync == false else {
            return "A synchronous typed adapter cannot implement an async requirement."
        }
        guard function.effects.isThrowing == method.isThrowing else {
            return "The typed adapter's throwing effect does not match the requirement."
        }
        guard method.typedErrorUsesIndirectResultSlot == false else {
            return "Typed closure adapters do not support a caller-provided indirect typed-error buffer."
        }
        guard function.parameters.count == method.argumentTypes.count + 1 else {
            return "The typed adapter must append one Stub.Invocation parameter after the requirement's \(method.argumentTypes.count) argument(s)."
        }
        for (offset, pair) in zip(function.parameters.dropLast(), method.argumentTypes)
            .enumerated()
        {
            guard ObjectIdentifier(pair.0.type) == ObjectIdentifier(pair.1) else {
                return "Typed adapter argument \(offset) is \(runtimeTypeName(pair.0.type)), expected \(runtimeTypeName(pair.1))."
            }
        }
        guard let lastParameter = function.parameters.last,
            ObjectIdentifier(lastParameter.type) == ObjectIdentifier(invocationType)
        else {
            return "The typed adapter's final parameter must be \(runtimeTypeName(invocationType))."
        }
        guard ObjectIdentifier(function.resultType) == ObjectIdentifier(method.returnType) else {
            return "The typed adapter returns \(runtimeTypeName(function.resultType)), expected \(runtimeTypeName(method.returnType))."
        }
        guard invocationArgumentIndex(for: method) != nil else {
            return "The requirement's explicit arguments leave no general-purpose argument register for its Stub.Invocation adapter parameter on this architecture."
        }
        return nil
    }

    package func invocationArgumentIndex(for method: MethodDescriptor) -> Int? {
        WitnessCallTransportPlan(
            method: method,
            trailingPayload: .typedAdapterInvocation
        ).typedAdapterInvocationArgumentIndex
    }
}

/// Retains the dispatch object explicitly appended to a thin adapter's
/// argument list for the lifetime of the fabricated witness table.
package final class TypedWitnessAdapter: @unchecked Sendable {
    package let target: UnsafeRawPointer
    package let invocation: UnsafeRawPointer
    private let retainedInvocation: AnyObject

    package init(
        target: UnsafeRawPointer,
        invocation: AnyObject
    ) {
        self.target = target
        self.invocation = UnsafeRawPointer(Unmanaged.passUnretained(invocation).toOpaque())
        retainedInvocation = invocation
    }
}
