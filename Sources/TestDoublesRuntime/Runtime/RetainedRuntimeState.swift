import TestDoublesRuntimeMetadata
package enum RetainedRuntimeState {
    package static func retain<State: AnyObject>(
        _ state: State
    ) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(state).toOpaque()
    }

    package static func borrow<State>(
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

    package static func consume<State>(
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
