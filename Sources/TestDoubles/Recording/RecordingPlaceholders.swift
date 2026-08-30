import Foundation

extension Match {
    /// Scoped and process-global factories for recording placeholder values.
    ///
    /// The recording pass behind `when`, `verify`, and `invocations` closures
    /// needs one valid temporary value per argument and result. TestDoubles
    /// synthesizes most types; class instances, existentials, and other layouts
    /// it cannot initialize safely normally take a value at each site through
    /// the `using:` and `returning:` overloads. Registering a factory supplies
    /// that value once for a whole suite instead:
    ///
    /// ```swift
    /// Match.Placeholders.register { User(name: "placeholder") }
    ///
    /// // Every later recording of a User argument or result just works:
    /// stub.when { $0.displayName(for: Match.any()) }.thenReturn("Blob")
    /// ```
    ///
    /// A factory value is used only while recording. It is never matched
    /// against, returned from a stubbed call, or retained past the recording
    /// pass. Explicit `using:` and `returning:` values win over task-scoped
    /// factories, task-scoped factories win over process-global registrations,
    /// and global registrations win over synthesized values. Factories match
    /// the exact registered type, so an existential and each concrete class
    /// register separately.
    ///
    /// Prefer ``withFactory(_:operation:)`` in individual or parallel tests.
    /// The registry used by ``register(_:_:)`` is shared by the whole test
    /// process; register in suite-level setup rather than in individual parallel
    /// tests, or ``unregister(_:)`` on the way out.
    public enum Placeholders {
        private typealias Factory = @Sendable () -> Any

        private static let lock = NSLock()
        nonisolated(unsafe) private static var factories: [ObjectIdentifier: Factory] = [:]
        @TaskLocal private static var scopedFactories: [ObjectIdentifier: Factory] = [:]

        /// Registers `make` as the recording placeholder factory for `Value`.
        /// The most recent registration for a type wins.
        public static func register<Value>(
            _ type: Value.Type = Value.self,
            _ make: @escaping @Sendable () -> Value
        ) {
            lock.lock()
            defer { lock.unlock() }
            factories[ObjectIdentifier(type)] = { make() }
        }

        /// Removes the factory for `Value`, restoring the default synthesis and
        /// `using:`/`returning:` contract.
        public static func unregister<Value>(_ type: Value.Type) {
            lock.lock()
            defer { lock.unlock() }
            factories.removeValue(forKey: ObjectIdentifier(type))
        }

        /// Runs `operation` with a task-scoped recording placeholder factory.
        ///
        /// The factory applies to the exact `Value` type in this lexical scope.
        /// Nested scopes inherit factories for other types and may override the
        /// same type until the nested operation returns. Structured child tasks
        /// inherit the scope; detached tasks do not.
        ///
        /// - Parameters:
        ///   - make: A factory that creates a valid temporary recording value.
        ///   - operation: The work that may resolve the scoped placeholder.
        /// - Returns: The value returned by `operation`.
        /// - Throws: The error thrown by `operation`.
        public static func withFactory<Value, Result, Failure: Error>(
            _ make: @escaping @Sendable () -> Value,
            operation: () throws(Failure) -> Result
        ) throws(Failure) -> Result {
            var overlay = scopedFactories
            overlay[ObjectIdentifier(Value.self)] = { make() }
            do {
                return try $scopedFactories.withValue(overlay) {
                    do {
                        return try operation()
                    } catch {
                        throw ClosureFailureTransport(error: error)
                    }
                }
            } catch let error as ClosureFailureTransport<Failure> {
                throw error.error
            } catch {
                preconditionFailure(
                    "[TestDoubles] Task-local placeholder storage unexpectedly threw \(error)."
                )
            }
        }

        /// Runs an asynchronous `operation` with a task-scoped recording
        /// placeholder factory.
        ///
        /// The factory applies to the exact `Value` type in this lexical scope
        /// and remains active across suspension points. Nested scopes inherit
        /// factories for other types and may temporarily override the same
        /// type. Structured child tasks inherit the scope; detached tasks do
        /// not.
        ///
        /// - Parameters:
        ///   - make: A factory that creates a valid temporary recording value.
        ///   - isolation: The actor isolation inherited by `operation`.
        ///   - operation: The asynchronous work that may resolve the scoped placeholder.
        /// - Returns: The value returned by `operation`.
        /// - Throws: The error thrown by `operation`.
        public static func withFactory<Value, Result, Failure: Error>(
            _ make: @escaping @Sendable () -> Value,
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws(Failure) -> Result
        ) async throws(Failure) -> Result {
            var overlay = scopedFactories
            overlay[ObjectIdentifier(Value.self)] = { make() }
            do {
                return try await $scopedFactories.withValue(overlay) {
                    do {
                        return try await operation()
                    } catch {
                        throw ClosureFailureTransport(error: error)
                    }
                }
            } catch let error as ClosureFailureTransport<Failure> {
                throw error.error
            } catch {
                preconditionFailure(
                    "[TestDoubles] Task-local placeholder storage unexpectedly threw \(error)."
                )
            }
        }

        /// Returns a registered placeholder for `type`, or `nil` when none is
        /// registered. The factory is user code, so it runs after the lock is
        /// released.
        static func make<Value>(_ type: Value.Type) -> Value? {
            if let factory = scopedFactories[ObjectIdentifier(type)] {
                return factory() as? Value
            }

            lock.lock()
            let factory = factories[ObjectIdentifier(type)]
            lock.unlock()
            guard let factory else { return nil }
            return factory() as? Value
        }
    }
}
