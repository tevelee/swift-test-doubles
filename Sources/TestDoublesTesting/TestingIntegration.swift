#if canImport(Testing)
    import IssueReporting
    @_spi(Testing) import TestDoubles
    import Testing

    /// A collection of automatic checks for a ``TestDoubleScope``.
    public struct TestDoubleStrictness: OptionSet, Sendable {
        /// The raw option value.
        public let rawValue: UInt8

        /// Creates a collection of automatic test-double checks.
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// Reports every `when` registration that no call matched.
        public static let noUnusedStubs = Self(rawValue: 1 << 0)

        /// Reports recorded calls that no successful `verify` covered.
        public static let noMoreInteractions = Self(rawValue: 1 << 1)

        /// Reports finite behavior queues that still have planned answers at teardown.
        public static let noUnconsumedBehaviorQueues = Self(rawValue: 1 << 2)

        /// Reports calls still parked by `thenSuspend()` at teardown.
        public static let noPendingSuspensions = Self(rawValue: 1 << 3)

        /// Reports callback captures still retaining callbacks at teardown.
        public static let noPendingCallbackCaptures = Self(rawValue: 1 << 4)

        /// Reports generated values, injected closures, or controllers that
        /// remain alive after the scoped test body returns.
        public static let noEscapedTestDoubles = Self(rawValue: 1 << 5)

        /// Reports async invocations that have not finished at teardown.
        public static let noUnfinishedAsyncInvocations = Self(rawValue: 1 << 6)

        /// Applies every automatic test-double check.
        public static let strict: Self = [
            .noUnusedStubs,
            .noMoreInteractions,
            .noUnconsumedBehaviorQueues,
            .noPendingSuspensions,
            .noPendingCallbackCaptures,
            .noEscapedTestDoubles,
            .noUnfinishedAsyncInvocations
        ]
    }

    /// A Swift Testing scope that checks test doubles created inside a test.
    ///
    /// Apply ``Trait/testDoubles`` to a test or suite. At teardown, the scope
    /// reports every `when` registration that no call matched. Use
    /// ``Trait/strictTestDoubles`` to also require every recorded call to be
    /// explicitly verified and every tracked queue, suspension, and callback
    /// capture to be finished.
    ///
    /// ```swift
    /// @Test(.testDoubles)
    /// func checkoutUsesItsConfiguredGateway() throws {
    ///     let gateway = try Stub<any PaymentGateway>()
    ///     gateway.when { $0.charge(amount: 42) }.thenReturn(.approved)
    ///
    ///     _ = try Checkout(gateway: gateway()).complete()
    /// }
    /// ```
    public struct TestDoubleScope: TestTrait, TestScoping {
        /// The teardown checks this scope applies.
        public let strictness: TestDoubleStrictness

        /// Creates a scope with the specified automatic teardown checks.
        ///
        /// The default reports unused registrations. Use ``TestDoubleStrictness/strict``
        /// to also require every recorded interaction to be explicitly verified,
        /// consume every finite queue, resume every suspended call, and release
        /// every captured callback.
        public init(strictness: TestDoubleStrictness = .noUnusedStubs) {
            self.strictness = strictness
        }

        /// Runs a test with automatic test-double teardown checks.
        public func provideScope(
            for test: Test,
            testCase: Test.Case?,
            performing function: () async throws -> Void
        ) async throws {
            let session = TestDoubleSession()
            do {
                try await TestDoubleTestingContext.$session.withValue(session) {
                    try await function()
                }
            } catch {
                report(diagnostics(from: session))
                attachFailureArtifacts(from: session)
                throw error
            }
            report(diagnostics(from: session))
            attachFailureArtifacts(from: session)
        }

        private func diagnostics(from session: TestDoubleSession) -> [String] {
            session.diagnostics(
                checkingUnusedRegistrations: strictness.contains(.noUnusedStubs),
                checkingUnverifiedInteractions: strictness.contains(.noMoreInteractions),
                checkingUnconsumedBehaviorQueues: strictness.contains(.noUnconsumedBehaviorQueues),
                checkingPendingSuspensions: strictness.contains(.noPendingSuspensions),
                checkingPendingCallbackCaptures: strictness.contains(.noPendingCallbackCaptures),
                checkingEscapedTestDoubles: strictness.contains(.noEscapedTestDoubles),
                checkingUnfinishedAsyncInvocations: strictness.contains(
                    .noUnfinishedAsyncInvocations
                )
            )
        }

        private func report(_ diagnostics: [String]) {
            for diagnostic in diagnostics {
                reportIssue("[TestDoubles] \(diagnostic)")
            }
        }

        private func attachFailureArtifacts(from session: TestDoubleSession) {
            for artifact in session.failureAttachments() {
                Attachment<String>.record(
                    artifact.contents,
                    named: artifact.name
                )
            }
        }
    }

    extension Trait where Self == TestDoubleScope {
        /// Reports registrations that no call matched for doubles created in this test.
        public static var testDoubles: Self { Self() }

        /// Applies every automatic test-double check.
        public static var strictTestDoubles: Self { Self(strictness: .strict) }

        /// Applies the specified teardown checks to doubles created in this test.
        public static func testDoubles(strictness: TestDoubleStrictness) -> Self {
            Self(strictness: strictness)
        }
    }
#endif
