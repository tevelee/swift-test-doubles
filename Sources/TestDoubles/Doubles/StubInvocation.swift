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

        init(recorder: StubRecorder, method: MethodDescriptor) {
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

            return try recorder.dispatchTyped(
                method: method,
                args: erased,
                as: resultType
            )
        }
    }
}
