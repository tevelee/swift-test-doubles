import Foundation

/// The lifecycle state of an ``AsyncStreamController`` or
/// ``AsyncThrowingStreamController``.
public enum AsyncStreamControllerTermination: Equatable, Sendable {
    /// The stream can still receive values.
    case active

    /// The controller finished the stream, with or without an error.
    case finished

    /// The consuming task cancelled iteration.
    case cancelled
}

private final class AsyncStreamControllerState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AsyncStreamControllerTermination = .active
    private var configuredName: String?

    var termination: AsyncStreamControllerTermination {
        lock.withLock { value }
    }

    func name(_ name: String) {
        lock.withLock { configuredName = name }
    }

    func terminate(_ termination: AsyncStreamControllerTermination) {
        lock.withLock {
            guard value == .active else { return }
            value = termination
        }
    }

    func teardownDiagnostic() -> String? {
        let snapshot = lock.withLock { (value, configuredName) }
        guard snapshot.0 == .active else { return nil }
        let label = snapshot.1.map { " '\($0)'" } ?? ""
        return "The async stream controller\(label) has not been finished or cancelled. "
            + "Call finish(), finish(throwing:), or cancel the consuming task before teardown."
    }
}

/// Drives an `AsyncStream` returned by a stubbed requirement.
///
/// Prefer ``CallPattern/thenStream(bufferingPolicy:)`` when configuring a
/// stub. The returned controller lets the test yield values and decide exactly
/// when the stream finishes.
public final class AsyncStreamController<Element>: @unchecked Sendable {
    /// The stream controlled by this value.
    public let stream: AsyncStream<Element>

    private let continuation: AsyncStream<Element>.Continuation
    private let state = AsyncStreamControllerState()

    /// Creates a controller with the requested buffering policy.
    public init(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
    ) {
        let pair = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        stream = pair.stream
        continuation = pair.continuation
        pair.continuation.onTermination = { [state] termination in
            switch termination {
                case .cancelled:
                    state.terminate(.cancelled)
                case .finished:
                    state.terminate(.finished)
                @unknown default:
                    state.terminate(.finished)
            }
        }
        TestDoubleTestingContext.session?.register(
            TestDoubleTeardownCheck(kind: .streamController) { [state] in
                state.teardownDiagnostic()
            },
        )
    }

    /// The current lifecycle state.
    public var termination: AsyncStreamControllerTermination {
        state.termination
    }

    /// Assigns a name used in automatic test-double teardown diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            trimmedName.isEmpty == false,
            "[TestDoubles] An async stream controller name must not be empty.",
        )
        state.name(trimmedName)
        return self
    }

    /// Delivers a value to the stream.
    @discardableResult
    public func yield(
        _ value: sending Element,
    ) -> AsyncStream<Element>.Continuation.YieldResult {
        continuation.yield(value)
    }

    /// Finishes the stream normally.
    public func finish() {
        state.terminate(.finished)
        continuation.finish()
    }
}

/// Drives an `AsyncThrowingStream` returned by a stubbed requirement.
///
/// Prefer ``CallPattern/thenThrowingStream(bufferingPolicy:)`` when configuring
/// a stub. The controller can finish normally or with any error.
public final class AsyncThrowingStreamController<Element>: @unchecked Sendable {
    /// The stream controlled by this value.
    public let stream: AsyncThrowingStream<Element, any Error>

    private let continuation: AsyncThrowingStream<Element, any Error>.Continuation
    private let state = AsyncStreamControllerState()

    /// Creates a controller with the requested buffering policy.
    public init(
        bufferingPolicy: AsyncThrowingStream<Element, any Error>.Continuation.BufferingPolicy = .unbounded,
    ) {
        let pair = AsyncThrowingStream<Element, any Error>.makeStream(
            bufferingPolicy: bufferingPolicy,
        )
        stream = pair.stream
        continuation = pair.continuation
        pair.continuation.onTermination = { [state] termination in
            switch termination {
                case .cancelled:
                    state.terminate(.cancelled)
                case .finished:
                    state.terminate(.finished)
                @unknown default:
                    state.terminate(.finished)
            }
        }
        TestDoubleTestingContext.session?.register(
            TestDoubleTeardownCheck(kind: .streamController) { [state] in
                state.teardownDiagnostic()
            },
        )
    }

    /// The current lifecycle state.
    public var termination: AsyncStreamControllerTermination {
        state.termination
    }

    /// Assigns a name used in automatic test-double teardown diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            trimmedName.isEmpty == false,
            "[TestDoubles] An async stream controller name must not be empty.",
        )
        state.name(trimmedName)
        return self
    }

    /// Delivers a value to the stream.
    @discardableResult
    public func yield(
        _ value: sending Element,
    ) -> AsyncThrowingStream<Element, any Error>.Continuation.YieldResult {
        continuation.yield(value)
    }

    /// Finishes the stream normally.
    public func finish() {
        state.terminate(.finished)
        continuation.finish()
    }

    /// Finishes the stream by throwing `error` from its iterator.
    public func finish(throwing error: any Error) {
        state.terminate(.finished)
        continuation.finish(throwing: error)
    }
}

extension CallPattern {
    /// Returns a controllable `AsyncStream` for every matching invocation.
    public func thenStream<Element>(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
    ) -> AsyncStreamController<Element> where Result == AsyncStream<Element> {
        let controller = AsyncStreamController<Element>(bufferingPolicy: bufferingPolicy)
        thenReturn(controller.stream, times: 1...)
        return controller
    }

    /// Returns a controllable throwing stream for every matching invocation.
    public func thenThrowingStream<Element>(
        bufferingPolicy: AsyncThrowingStream<Element, any Error>.Continuation.BufferingPolicy = .unbounded,
    ) -> AsyncThrowingStreamController<Element>
    where Result == AsyncThrowingStream<Element, any Error> {
        let controller = AsyncThrowingStreamController<Element>(bufferingPolicy: bufferingPolicy)
        thenReturn(controller.stream, times: 1...)
        return controller
    }
}

extension Stub {
    /// Describes a synchronous requirement that returns an `AsyncStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenStream<Element>(
        _ call: (P) throws -> AsyncStream<Element>,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) -> CallPattern<AsyncStream<Element>> {
        let placeholder = AsyncStream<Element> { $0.finish() }
        return when(
            returning: placeholder,
            call,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }

    /// Describes an async requirement that returns an `AsyncStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenStream<Element>(
        _ call: (P) async throws -> AsyncStream<Element>,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async -> CallPattern<AsyncStream<Element>> {
        let placeholder = AsyncStream<Element> { $0.finish() }
        return await when(
            returning: placeholder,
            call,
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }

    /// Describes a synchronous requirement that returns an
    /// `AsyncThrowingStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenThrowingStream<Element>(
        _ call: (P) throws -> AsyncThrowingStream<Element, any Error>,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) -> CallPattern<AsyncThrowingStream<Element, any Error>> {
        let placeholder = AsyncThrowingStream<Element, any Error> { $0.finish() }
        return when(
            returning: placeholder,
            call,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }

    /// Describes an async requirement that returns an
    /// `AsyncThrowingStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenThrowingStream<Element>(
        _ call: (P) async throws -> AsyncThrowingStream<Element, any Error>,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async -> CallPattern<AsyncThrowingStream<Element, any Error>> {
        let placeholder = AsyncThrowingStream<Element, any Error> { $0.finish() }
        return await when(
            returning: placeholder,
            call,
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }
}

extension ManualStub {
    /// Describes a synchronous manual requirement that returns an `AsyncStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenStream<Element>(
        _ call: (T) throws -> AsyncStream<Element>,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) -> CallPattern<AsyncStream<Element>> {
        let placeholder = AsyncStream<Element> { $0.finish() }
        return when(
            returning: placeholder,
            call,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }

    /// Describes an async manual requirement that returns an `AsyncStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenStream<Element>(
        _ call: (T) async throws -> AsyncStream<Element>,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async -> CallPattern<AsyncStream<Element>> {
        let placeholder = AsyncStream<Element> { $0.finish() }
        return await when(
            returning: placeholder,
            call,
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }

    /// Describes a synchronous manual requirement that returns an
    /// `AsyncThrowingStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenThrowingStream<Element>(
        _ call: (T) throws -> AsyncThrowingStream<Element, any Error>,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) -> CallPattern<AsyncThrowingStream<Element, any Error>> {
        let placeholder = AsyncThrowingStream<Element, any Error> { $0.finish() }
        return when(
            returning: placeholder,
            call,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }

    /// Describes an async manual requirement that returns an
    /// `AsyncThrowingStream`.
    ///
    /// This supplies the temporary recording placeholder automatically.
    public func whenThrowingStream<Element>(
        _ call: (T) async throws -> AsyncThrowingStream<Element, any Error>,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
    ) async -> CallPattern<AsyncThrowingStream<Element, any Error>> {
        let placeholder = AsyncThrowingStream<Element, any Error> { $0.finish() }
        return await when(
            returning: placeholder,
            call,
            isolation: isolation,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column,
        )
    }
}
