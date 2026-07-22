enum RetainedRuntimeState {
    static func retain<State: AnyObject>(
        _ state: State
    ) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(state).toOpaque()
    }

    static func borrow<State>(
        _ type: State.Type,
        from pointer: UnsafeRawPointer,
        invalidTypeMessage: @autoclosure () -> String
    ) -> State {
        let object = Unmanaged<AnyObject>.fromOpaque(pointer)
            .takeUnretainedValue()
        guard let state = object as? State else {
            preconditionFailure(invalidTypeMessage())
        }
        return state
    }

    static func consume<State>(
        _ type: State.Type,
        from pointer: UnsafeRawPointer,
        invalidTypeMessage: @autoclosure () -> String
    ) -> State {
        let object = Unmanaged<AnyObject>.fromOpaque(pointer)
            .takeRetainedValue()
        guard let state = object as? State else {
            preconditionFailure(invalidTypeMessage())
        }
        return state
    }
}
