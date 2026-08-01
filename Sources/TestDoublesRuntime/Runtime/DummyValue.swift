import Echo
import EchoRuntimeSupport

/// Extends safe placeholder synthesis with fail-closed function values for Dummy.
package enum DummyValue {
    package static func make<T>(_ type: T.Type = T.self) -> T? {
        if let value = PlaceholderValue.make(type) {
            return value
        }

        guard let metadata = reflect(type) as? FunctionMetadata else {
            return nil
        }

        switch metadata.flags.convention {
            case .swift:
                if metadata.flags.isAsync {
                    let function: () async -> Never = {
                        dummyFunctionWasInvoked()
                    }
                    return copyFunction(function, as: type)
                }
                let function: () -> Never = {
                    dummyFunctionWasInvoked()
                }
                return copyFunction(function, as: type)

            case .thin:
                if metadata.flags.isAsync {
                    let function: @convention(thin) () async -> Void = {
                        dummyFunctionWasInvoked()
                    }
                    return copyFunction(function, as: type)
                }
                let function: @convention(thin) () -> Void = {
                    dummyFunctionWasInvoked()
                }
                return copyFunction(function, as: type)

            case .c:
                let function: @convention(c) () -> Void = {
                    dummyFunctionWasInvoked()
                }
                return copyFunction(function, as: type)

            case .block:
                #if canImport(ObjectiveC)
                    let function: @convention(block) () -> Void = {
                        dummyFunctionWasInvoked()
                    }
                    return copyFunction(function, as: type)
                #else
                    return nil
                #endif
        }
    }

    private static func copyFunction<T, Function>(
        _ function: Function,
        as type: T.Type
    ) -> T? {
        let metadata = reflect(type)
        guard metadata.vwt.size == MemoryLayout<Function>.size else {
            return nil
        }

        let storage = ValueStorage.allocate(for: type)
        defer { storage.deallocate() }

        var function = function
        withUnsafePointer(to: &function) { source in
            ValueOperations.initializeCopy(
                of: type,
                from: UnsafeRawPointer(source),
                to: storage
            )
        }
        return storage.assumingMemoryBound(to: T.self).move()
    }
}

// swiftlint:disable:next unavailable_function
private func dummyFunctionWasInvoked() -> Never {
    fatalError(
        "[TestDoubles] A dummy function was invoked. A dummy may only be passed "
            + "to code paths that do not use it."
    )
}
