/// Generic dispatch bridge for runtime-compiled mock types.
///
/// The compiled dylib imports TestDoubles and calls these directly.
/// Fully type-agnostic — works for any argument and return type.
enum MockBridge {

    /// Dispatch returning R.
    static func dispatch<R>(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) -> R {
        let recorder = MockRegistry.resolve(ctx)
        let result = recorder.dispatch(method: slot, args: args)
        if recorder.mode != .normal { return zeroValue(R.self) }
        return result as! R
    }

    /// Throwing dispatch returning R.
    static func throwingDispatch<R>(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) throws -> R {
        let recorder = MockRegistry.resolve(ctx)
        if let throwingResult = recorder.dispatchThrowing(method: slot, args: args) {
            if recorder.mode != .normal { return zeroValue(R.self) }
            switch throwingResult {
            case .success(let value): return value as! R
            case .failure(let error): throw error
            }
        }
        let result = recorder.dispatch(method: slot, args: args)
        if recorder.mode != .normal { return zeroValue(R.self) }
        return result as! R
    }

    /// Void dispatch.
    static func dispatchVoid(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) {
        let recorder = MockRegistry.resolve(ctx)
        _ = recorder.dispatch(method: slot, args: args)
    }

    /// Void throwing dispatch.
    static func throwingDispatchVoid(_ ctx: UnsafeRawPointer, slot: Int, args: [Any] = []) throws {
        let recorder = MockRegistry.resolve(ctx)
        if let throwingResult = recorder.dispatchThrowing(method: slot, args: args) {
            switch throwingResult {
            case .success: return
            case .failure(let error): throw error
            }
        }
        _ = recorder.dispatch(method: slot, args: args)
    }
}
