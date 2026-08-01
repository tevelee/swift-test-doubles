import Echo
import EchoRuntimeSupport

/// Extends safe placeholder synthesis with fail-closed function values for Dummy.
package enum DummyValue {
    package static func make<T>(_ type: T.Type = T.self) -> T? {
        PlaceholderValue.make(type, includingDummyValues: true)
    }

    struct FunctionPlan {
        let type: Any.Type
        let convention: FunctionConvention
        let isAsync: Bool
    }

    static func functionPlan(for type: Any.Type) -> FunctionPlan? {
        guard let metadata = reflect(type) as? FunctionMetadata else {
            return nil
        }
        #if !canImport(ObjectiveC)
            guard metadata.flags.convention != .block else { return nil }
        #endif
        return FunctionPlan(
            type: type,
            convention: metadata.flags.convention,
            isAsync: metadata.flags.isAsync
        )
    }

    static func initialize(
        _ plan: FunctionPlan,
        at destination: UnsafeMutableRawPointer
    ) {
        switch plan.convention {
            case .swift:
                if plan.isAsync {
                    let function: () async -> Never = {
                        dummyFunctionWasInvoked()
                    }
                    copyFunction(function, as: plan.type, to: destination)
                    return
                }
                let function: () -> Never = {
                    dummyFunctionWasInvoked()
                }
                copyFunction(function, as: plan.type, to: destination)

            case .thin:
                if plan.isAsync {
                    let function: @convention(thin) () async -> Void = {
                        dummyFunctionWasInvoked()
                    }
                    copyFunction(function, as: plan.type, to: destination)
                    return
                }
                let function: @convention(thin) () -> Void = {
                    dummyFunctionWasInvoked()
                }
                copyFunction(function, as: plan.type, to: destination)

            case .c:
                let function: @convention(c) () -> Void = {
                    dummyFunctionWasInvoked()
                }
                copyFunction(function, as: plan.type, to: destination)

            case .block:
                #if canImport(ObjectiveC)
                    let function: @convention(block) () -> Void = {
                        dummyFunctionWasInvoked()
                    }
                    copyFunction(function, as: plan.type, to: destination)
                #else
                    preconditionFailure(
                        "[TestDoubles] Objective-C block dummy plan escaped validation."
                    )
                #endif
        }
    }

    private static func copyFunction<Function>(
        _ function: Function,
        as type: Any.Type,
        to destination: UnsafeMutableRawPointer
    ) {
        let metadata = reflect(type)
        precondition(metadata.vwt.size == MemoryLayout<Function>.size)

        var function = function
        withUnsafePointer(to: &function) { source in
            ValueOperations.initializeCopy(
                of: type,
                from: UnsafeRawPointer(source),
                to: destination
            )
        }
    }
}

// swiftlint:disable:next unavailable_function
private func dummyFunctionWasInvoked() -> Never {
    fatalError(
        "[TestDoubles] A dummy function was invoked. A dummy may only be passed "
            + "to code paths that do not use it."
    )
}
