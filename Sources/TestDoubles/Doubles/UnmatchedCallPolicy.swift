/// How a double answers a call that no registration matched.
///
/// A double traps by default: an unconfigured call is a test bug, and stopping
/// at the call keeps the diagnostic next to the code that made it. Trapping
/// ends the whole test process though, so one missing registration discards
/// every other result in the same run. Choose ``reportIssue`` when a run that
/// keeps going is worth more than stopping at the exact call.
public struct UnmatchedCallPolicy: Sendable {
    enum Kind: Sendable {
        case trap
        case reportIssue(recover: (@Sendable (Any.Type) -> Any?)?)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    /// Terminates the test process with the missing-stub diagnostic.
    ///
    /// This is the default.
    public static let trap = Self(kind: .trap)

    /// Reports the missing-stub diagnostic as a test issue and recovers with a
    /// synthesized placeholder for the requirement's result type.
    ///
    /// Recovery uses the same synthesis as ``Dummy``, so a `Void` requirement
    /// simply returns, a concrete result becomes an unspecified placeholder,
    /// and a protocol result becomes a fail-on-use existential that traps if
    /// the code under test calls anything on it. A result type that cannot be
    /// synthesized has no value to return, so that call still traps and the
    /// diagnostic says why recovery was impossible.
    ///
    /// The call is recorded, so it appears in the interaction history and in
    /// ``Stub/verifyNoMoreInteractions(fileID:filePath:line:column:)``.
    public static let reportIssue = Self(kind: .reportIssue(recover: nil))

    /// Reports the missing-stub diagnostic as a test issue and recovers with
    /// the value `recover` supplies for the requirement's result type.
    ///
    /// Use this for result types automatic synthesis cannot build. Returning
    /// `nil`, or a value that is not of the requested type, falls back to
    /// automatic synthesis and then to trapping.
    ///
    /// - Parameter recover: Builds a recovery value for one result type.
    public static func reportIssue(
        recoveringWith recover: @escaping @Sendable (Any.Type) -> Any?
    ) -> Self {
        Self(kind: .reportIssue(recover: recover))
    }
}

/// Builds the value an unmatched call returns once its issue is reported.
enum UnmatchedCallRecovery {
    /// Synthesizes a placeholder of `type`, or `nil` when none is safe.
    static func placeholder(ofType type: Any.Type) -> Any? {
        if type == Void.self {
            return ()
        }

        func open<T>(_ type: T.Type) -> Any? {
            guard let dummy = try? Dummy<T>() else { return nil }
            return dummy()
        }
        return _openExistential(type, do: open)
    }

    /// Whether `value` can stand in for a result of `type`.
    static func value(_ value: Any, matches type: Any.Type) -> Bool {
        if type == Void.self {
            return true
        }

        func matches<Expected>(_ type: Expected.Type) -> Bool {
            value is Expected
        }
        return _openExistential(type, do: matches)
    }
}

extension Stub {
    /// Chooses how this double answers a call no registration matched.
    ///
    /// ```swift
    /// let gateway = try Stub<any PaymentGateway>().onUnmatchedCall(.reportIssue)
    /// ```
    ///
    /// - Parameter policy: The policy to apply from the next call on.
    /// - Returns: This double, so construction and configuration can chain.
    @discardableResult
    public func onUnmatchedCall(_ policy: UnmatchedCallPolicy) -> Self {
        recorder.setUnmatchedCallPolicy(policy)
        return self
    }
}

extension ManualStub {
    /// Chooses how this double answers a call no registration matched.
    ///
    /// - Parameter policy: The policy to apply from the next call on.
    /// - Returns: This double, so construction and configuration can chain.
    @discardableResult
    public func onUnmatchedCall(_ policy: UnmatchedCallPolicy) -> Self {
        recorder.setUnmatchedCallPolicy(policy)
        return self
    }
}
