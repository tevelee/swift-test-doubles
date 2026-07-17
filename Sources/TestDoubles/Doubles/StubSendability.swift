/// Acknowledges the unchecked concurrency boundary of a runtime-generated
/// existential whose protocol conforms to `Sendable`.
///
/// TestDoubles synchronizes its recorder, but Swift cannot prove that every
/// configured value, matcher, captor, handler, or recorded invocation argument
/// is safe to transfer between concurrency domains. Pass ``unchecked`` only
/// after ensuring that state is safe for the way the generated value is used.
public enum StubSendability: Sendable {
    /// Explicitly accepts responsibility for the generated value's unchecked
    /// `Sendable` state.
    case unchecked
}
