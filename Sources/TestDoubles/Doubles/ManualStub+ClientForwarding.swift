extension ManualStub {
    func dispatchValue<R>(
        method: ManualMethod,
        args: [Any],
        forwardingTo fallback: @escaping () -> R
    ) -> R {
        do {
            return try dispatchThrowingValue(
                method: method,
                args: args,
                forwardingTo: fallback
            )
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing client fallback for '\(method.name)' threw \(error)."
            )
        }
    }

    func dispatchThrowingValue<R>(
        method: ManualMethod,
        args: [Any],
        forwardingTo fallback: @escaping () throws -> R
    ) throws -> R {
        try recorder.dispatchTyped(
            manualMethod: method,
            args: args,
            as: R.self,
            forwardingTo: fallback
        )
    }

    func dispatchThrowingValue<R, Failure: Error>(
        method: ManualMethod,
        args: [Any],
        throwing failureType: Failure.Type,
        forwardingTo fallback: @escaping () throws(Failure) -> R
    ) throws(Failure) -> R {
        do {
            return try dispatchThrowingValue(
                method: method,
                args: args,
                forwardingTo: fallback
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            failClientTypedErrorMismatch(
                method: method.name,
                expected: failureType,
                actual: error,
                forwardingMethod: "throwingFunction"
            )
        }
    }

    func dispatchAsyncValue<R>(
        method: ManualMethod,
        args: [Any],
        forwardingTo fallback: () async -> R
    ) async -> R {
        do {
            return try await dispatchAsyncThrowingValue(
                method: method,
                args: args,
                forwardingTo: fallback
            )
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing async client fallback for '\(method.name)' threw \(error)."
            )
        }
    }

    func dispatchAsyncThrowingValue<R>(
        method: ManualMethod,
        args: [Any],
        forwardingTo fallback: () async throws -> R
    ) async throws -> R {
        switch recorder.prepareAsyncDispatch(manualMethod: method, args: args) {
            case .placeholder:
                return RecordingReturnPlaceholderContext.requiredValue(
                    for: R.self,
                    method: method.name
                )
            case .immediate(.success(let result)):
                return requireStubbedResult(result, as: R.self, method: method.name)
            case .immediate(.failure(let error)):
                throw error
            case .suspending(let handler):
                return requireStubbedResult(
                    try await handler(args),
                    as: R.self,
                    method: method.name
                )
            case .forwarding(let token):
                defer {
                    recorder.completeInvocation(token, outcome: .forwarded)
                }
                return try await fallback()
        }
    }

    func dispatchAsyncThrowingValue<R, Failure: Error>(
        method: ManualMethod,
        args: [Any],
        throwing failureType: Failure.Type,
        forwardingTo fallback: () async throws(Failure) -> R
    ) async throws(Failure) -> R {
        do {
            return try await dispatchAsyncThrowingValue(
                method: method,
                args: args,
                forwardingTo: fallback
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            failClientTypedErrorMismatch(
                method: method.name,
                expected: failureType,
                actual: error,
                forwardingMethod: "asyncThrowingFunction"
            )
        }
    }

    private func failClientTypedErrorMismatch<Failure: Error>(
        method: String,
        expected: Failure.Type,
        actual: any Error,
        forwardingMethod: String
    ) -> Never {
        fatalError(
            "[TestDoubles] Typed client handler error mismatch for '\(method)': "
                + "expected \(expected), got \(type(of: actual)). Configure a \(expected) "
                + "error or use the untyped `\(forwardingMethod)` overload."
        )
    }
}
