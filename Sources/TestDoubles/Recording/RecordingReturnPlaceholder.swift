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
