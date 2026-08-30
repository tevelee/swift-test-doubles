#if canImport(Testing)
    import IssueReporting
    @_spi(Testing) import TestDoubles

    extension TestDoubleStrictness {
        /// Checks deterministic unfinished-resource state without requiring
        /// every interaction to be verified or every controller to be released.
        public static let lifecycle: Self = [
            .noUnconsumedBehaviorQueues,
            .noPendingSuspensions,
            .noPendingCallbackCaptures,
            .noUnfinishedAsyncInvocations,
            .noUnconsumedInvocationStreams,
            .noOpenStreamControllers
        ]
    }

    enum ScopedTestDoubleValidation {
        static func issues(
            from session: TestDoubleSession,
            checking strictness: TestDoubleStrictness
        ) -> [TestDoubleIssue] {
            session.issues(
                checkingUnusedRegistrations: strictness.contains(.noUnusedStubs),
                checkingUnverifiedInteractions: strictness.contains(.noMoreInteractions),
                checkingUnconsumedBehaviorQueues: strictness.contains(
                    .noUnconsumedBehaviorQueues
                ),
                checkingPendingSuspensions: strictness.contains(.noPendingSuspensions),
                checkingPendingCallbackCaptures: strictness.contains(
                    .noPendingCallbackCaptures
                ),
                checkingEscapedTestDoubles: strictness.contains(.noEscapedTestDoubles),
                checkingUnfinishedAsyncInvocations: strictness.contains(
                    .noUnfinishedAsyncInvocations
                ),
                checkingUnconsumedInvocationStreams: strictness.contains(
                    .noUnconsumedInvocationStreams
                ),
                checkingOpenStreamControllers: strictness.contains(
                    .noOpenStreamControllers
                )
            )
        }

        static func report(
            _ issues: [TestDoubleIssue],
            fileID: StaticString,
            filePath: StaticString,
            line: UInt,
            column: UInt
        ) {
            for issue in issues {
                reportIssue(
                    "[TestDoubles] \(issue)",
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            }
        }
    }

    extension TestDouble {
        /// Runs `operation` in a task-local test-double scope and reports the
        /// selected teardown checks when the operation returns or throws.
        ///
        /// Use this lexical form from XCTest, custom test harnesses, or a
        /// helper that cannot carry a Swift Testing trait. Structured child
        /// tasks inherit the scope; detached tasks do not.
        public static func withScope<Result, Failure: Error>(
            checking strictness: TestDoubleStrictness = .noUnusedStubs,
            named name: String = #function,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column,
            _ operation: () throws(Failure) -> Result
        ) throws(Failure) -> Result {
            let session = TestDoubleSession(automaticNamePrefix: name)
            defer {
                ScopedTestDoubleValidation.report(
                    ScopedTestDoubleValidation.issues(
                        from: session,
                        checking: strictness
                    ),
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            }
            do {
                return try TestDoubleTestingContext.$session.withValue(session) {
                    try operation()
                }
            } catch let error as Failure {
                throw error
            } catch {
                preconditionFailure(
                    "[TestDoubles] A typed lexical scope unexpectedly threw \(error)."
                )
            }
        }

        /// Asynchronous counterpart to ``withScope(checking:named:fileID:filePath:line:column:_:)``.
        public static func withScope<Result, Failure: Error>(
            checking strictness: TestDoubleStrictness = .noUnusedStubs,
            named name: String = #function,
            isolation: isolated (any Actor)? = #isolation,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column,
            _ operation: () async throws(Failure) -> Result
        ) async throws(Failure) -> Result {
            let session = TestDoubleSession(automaticNamePrefix: name)
            defer {
                ScopedTestDoubleValidation.report(
                    ScopedTestDoubleValidation.issues(
                        from: session,
                        checking: strictness
                    ),
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            }
            do {
                return try await TestDoubleTestingContext.$session.withValue(session) {
                    try await operation()
                }
            } catch let error as Failure {
                throw error
            } catch {
                preconditionFailure(
                    "[TestDoubles] A typed asynchronous lexical scope unexpectedly threw \(error)."
                )
            }
        }
    }
#endif
