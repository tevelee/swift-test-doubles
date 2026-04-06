#if COMPILED_STUB && os(macOS)
/// Generic dispatch bridge for runtime-compiled mock types.
///
/// The compiled dylib imports TestDoubles and calls these directly.
/// Fully type-agnostic — works for any argument and return type.
public enum MockBridge {

    /// Dispatch returning R.
    public static func dispatch<R>(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) -> R {
        guard let recorder = MockRegistry.resolveOptional(ctx) else {
            preconditionFailure("[TestDoubles] No mock registered for this context. The RuntimeStub may have been deallocated before the mock was used. Ensure the stub is retained for the lifetime of the test.")
        }
        let result = recorder.dispatch(method: slot, args: args)
        if recorder.mode != .normal { return zeroValue(R.self) }
        guard let typed = result as? R else {
            preconditionFailure("[TestDoubles] Type mismatch in dispatch at slot \(slot): expected \(R.self), got \(type(of: result)). Verify your .returns() type matches the method signature.")
        }
        return typed
    }

    /// Throwing dispatch returning R.
    public static func throwingDispatch<R>(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) throws -> R {
        guard let recorder = MockRegistry.resolveOptional(ctx) else {
            preconditionFailure("[TestDoubles] No mock registered for this context. The RuntimeStub may have been deallocated before the mock was used. Ensure the stub is retained for the lifetime of the test.")
        }
        if let throwingResult = recorder.dispatchThrowing(method: slot, args: args) {
            if recorder.mode != .normal { return zeroValue(R.self) }
            switch throwingResult {
            case .success(let value):
                guard let typed = value as? R else {
                    preconditionFailure("[TestDoubles] Type mismatch in throwing dispatch at slot \(slot): expected \(R.self), got \(type(of: value)). Verify your .returns() type matches the method signature.")
                }
                return typed
            case .failure(let error): throw error
            }
        }
        let result = recorder.dispatch(method: slot, args: args)
        if recorder.mode != .normal { return zeroValue(R.self) }
        guard let typed = result as? R else {
            preconditionFailure("[TestDoubles] Type mismatch in dispatch at slot \(slot): expected \(R.self), got \(type(of: result)). Verify your .returns() type matches the method signature.")
        }
        return typed
    }

    /// Void dispatch.
    public static func dispatchVoid(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) {
        guard let recorder = MockRegistry.resolveOptional(ctx) else {
            preconditionFailure("[TestDoubles] No mock registered for this context. The RuntimeStub may have been deallocated before the mock was used. Ensure the stub is retained for the lifetime of the test.")
        }
        _ = recorder.dispatch(method: slot, args: args)
    }

    /// Void throwing dispatch.
    public static func throwingDispatchVoid(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) throws {
        guard let recorder = MockRegistry.resolveOptional(ctx) else {
            preconditionFailure("[TestDoubles] No mock registered for this context. The RuntimeStub may have been deallocated before the mock was used. Ensure the stub is retained for the lifetime of the test.")
        }
        if let throwingResult = recorder.dispatchThrowing(method: slot, args: args) {
            switch throwingResult {
            case .success: return
            case .failure(let error): throw error
            }
        }
        _ = recorder.dispatch(method: slot, args: args)
    }
}
#endif
