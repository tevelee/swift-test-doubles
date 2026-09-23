import Foundation

/// A closure argument lent to a compiled stub for the duration of one call.
///
/// Swift forbids storing a nonescaping closure, while a stub records every
/// argument it receives. A conformer forwards a nonescaping closure by making
/// it escapable with `withoutActuallyEscaping`, lending it through a
/// `BorrowedClosure`, and passing a proxy that calls through the borrow.
/// Ending the borrow before the call returns releases the original closure,
/// so it never outlives the call. The recorded proxy stays valid to compare,
/// but calling it later terminates with a diagnostic:
///
/// ```swift
/// func map(_ values: [Int], transform: (Int) -> Int) -> [Int] {
///     withoutActuallyEscaping(transform) { transform in
///         let borrowed = BorrowedClosure(transform)
///         defer { borrowed.end() }
///         return stub.call(values, { (value: Int) -> Int in
///             borrowed { $0(value) }
///         })
///     }
/// }
/// ```
///
/// The manual stub generator emits this forwarding for nonescaping closure
/// parameters automatically.
public class BorrowedArgument: @unchecked Sendable {
    fileprivate let lock = NSLock()
    fileprivate var threw = false

    fileprivate init() {}

    /// Whether the borrowed closure threw during the current call.
    var didThrow: Bool {
        lock.withLock { threw }
    }
}

/// A typed closure argument lent to a compiled stub for one call.
///
/// See ``BorrowedArgument`` for the forwarding pattern.
public final class BorrowedClosure<Function>: BorrowedArgument, @unchecked Sendable {
    private var stored: Function?
    private let parameterDescription: String

    /// Lends `function` until ``end()``.
    ///
    /// - Parameters:
    ///   - function: The closure argument, made escapable for this call.
    ///   - parameter: The parameter name used in diagnostics.
    public init(_ function: Function, parameter: String = "closure") {
        stored = function
        parameterDescription = parameter
        super.init()
    }

    /// Calls the borrowed closure through `invoke`.
    ///
    /// Terminates with a diagnostic when the call that lent the closure has
    /// already returned.
    public func callAsFunction<Result, Failure: Error>(
        _ invoke: (Function) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let function = requireFunction()
        do {
            return try invoke(function)
        } catch {
            lock.withLock { threw = true }
            throw error
        }
    }

    /// Calls the borrowed asynchronous closure through `invoke`.
    public func callAsFunction<Result, Failure: Error>(
        isolation: isolated (any Actor)? = #isolation,
        _ invoke: (Function) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        let function = requireFunction()
        do {
            return try await invoke(function)
        } catch {
            lock.withLock { threw = true }
            throw error
        }
    }

    /// Releases the borrowed closure. Call it before the lending call returns.
    public func end() {
        lock.withLock { stored = nil }
    }

    private func requireFunction() -> Function {
        guard let function = lock.withLock({ stored }) else {
            fatalError(
                "[TestDoubles] The nonescaping closure argument '\(parameterDescription)' was "
                    + "called after the call that received it returned. A nonescaping "
                    + "closure can only be called while its call is running; call it from "
                    + "the stub's handler instead of storing it."
            )
        }
        return function
    }
}

extension CompiledStub {
    /// Runs the forwarding call of a `rethrows` requirement.
    ///
    /// A `rethrows` requirement may throw only an error that one of its closure
    /// arguments threw. This method rethrows an error only when a borrowed
    /// closure threw during `body`, and terminates with a diagnostic when a
    /// configured behavior throws on its own, because the caller may have
    /// passed a nonthrowing closure and cannot handle the error.
    public func rethrowingCall<Result>(
        borrowing arguments: BorrowedArgument...,
        function: String = #function,
        _ body: () throws -> Result
    ) throws -> Result {
        do {
            return try body()
        } catch {
            try Self.rethrow(error, borrowing: arguments, function: function)
        }
    }

    /// Asynchronous variant of ``rethrowingCall(borrowing:function:_:)``.
    public func rethrowingCall<Result>(
        borrowing arguments: BorrowedArgument...,
        function: String = #function,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await body()
        } catch {
            try Self.rethrow(error, borrowing: arguments, function: function)
        }
    }

    private static func rethrow(
        _ error: any Error,
        borrowing arguments: [BorrowedArgument],
        function: String
    ) throws -> Never {
        guard arguments.contains(where: \.didThrow) else {
            fatalError(
                "[TestDoubles] '\(function)' rethrows, so it can only throw an error "
                    + "its closure argument threw, but the configured behavior threw "
                    + "\(error) without the closure throwing. Call the closure from the "
                    + "handler to propagate its error, or return a value."
            )
        }
        throw error
    }
}
