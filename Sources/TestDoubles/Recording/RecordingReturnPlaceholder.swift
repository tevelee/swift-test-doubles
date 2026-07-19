struct ClosureFailureTransport<Failure: Error>: Error {
    let error: Failure
}

final class RecordingReturnPlaceholderBox: @unchecked Sendable {
    let value: Any

    init<Value>(_ value: Value) {
        self.value = value
    }
}

enum RecordingReturnPlaceholderContext {
    @TaskLocal private static var current: RecordingReturnPlaceholderBox?

    static var box: RecordingReturnPlaceholderBox? {
        current
    }

    static func requiredValue<Result>(
        for type: Result.Type,
        method: String
    ) -> Result {
        if let box {
            guard let value = box.value as? Result else {
                fatalError(
                    "[TestDoubles] Recording placeholder for '\(method)' is "
                        + "\(Swift.type(of: box.value)), expected \(type)."
                )
            }
            return value
        }
        guard let placeholder = PlaceholderValue.make(type) else {
            fatalError(
                "[TestDoubles] Cannot synthesize a recording placeholder for \(type). "
                    + "Use the `returning:` placeholder overload of `when`/`verify` instead."
            )
        }
        return placeholder
    }

    static func withValue<Placeholder, Result, Failure: Error>(
        _ placeholder: Placeholder,
        _ operation: () throws(Failure) -> Result
    ) throws(Failure) -> Result {
        do {
            return try $current.withValue(RecordingReturnPlaceholderBox(placeholder)) {
                do {
                    return try operation()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure("[TestDoubles] Task-local placeholder storage unexpectedly threw \(error).")
        }
    }

    static func withValue<Placeholder, Result, Failure: Error>(
        _ placeholder: Placeholder,
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        do {
            return try await $current.withValue(RecordingReturnPlaceholderBox(placeholder)) {
                do {
                    return try await operation()
                } catch {
                    throw ClosureFailureTransport(error: error)
                }
            }
        } catch let error as ClosureFailureTransport<Failure> {
            throw error.error
        } catch {
            preconditionFailure("[TestDoubles] Task-local placeholder storage unexpectedly threw \(error).")
        }
    }
}

func requireStubbedResult<Result>(
    _ value: Any,
    as type: Result.Type,
    method: String
) -> Result {
    guard let typed = value as? Result else {
        fatalError("[TestDoubles] Stubbed return for '\(method)' is not \(type).")
    }
    return typed
}
