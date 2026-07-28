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

    /// Applies every automatic test-double check.
    public static let strict: Self = [.noUnusedStubs, .noMoreInteractions]
}

/// A Swift Testing scope that checks test doubles created inside a test.
///
/// Apply ``Trait/testDoubles`` to a test or suite. At teardown, the scope
/// reports every `when` registration that no call matched. Use
/// ``Trait/strictTestDoubles`` to also require every recorded call to be
/// explicitly verified.
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
    /// to also require every recorded interaction to be explicitly verified.
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
            report(
                session.diagnostics(
                    checkingUnusedRegistrations: strictness.contains(.noUnusedStubs),
                    checkingUnverifiedInteractions: strictness.contains(.noMoreInteractions)
                ))
            throw error
        }
        report(
            session.diagnostics(
                checkingUnusedRegistrations: strictness.contains(.noUnusedStubs),
                checkingUnverifiedInteractions: strictness.contains(.noMoreInteractions)
            ))
    }

    private func report(_ diagnostics: [String]) {
        for diagnostic in diagnostics {
            reportIssue("[TestDoubles] \(diagnostic)")
        }
    }
}

extension Trait where Self == TestDoubleScope {
    /// Reports registrations that no call matched for doubles created in this test.
    public static var testDoubles: Self { Self() }

    /// Reports unused registrations and interactions not covered by `verify`.
    public static var strictTestDoubles: Self { Self(strictness: .strict) }

    /// Applies the specified teardown checks to doubles created in this test.
    public static func testDoubles(strictness: TestDoubleStrictness) -> Self {
        Self(strictness: strictness)
    }
}
