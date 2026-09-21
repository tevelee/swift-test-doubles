#if canImport(Dispatch)
    import Dispatch

    /// Starts synchronous work that parks its thread until another thread
    /// releases it, without holding a cooperative executor thread.
    ///
    /// The cooperative pool runs one thread per active core, so a `Task` whose
    /// body blocks on a lock or condition holds one of those threads until it
    /// is released. Tests that gate a matcher this way need the releasing side
    /// to keep running, and on a machine with few cores, or with several test
    /// bodies in flight at once, the pool can be fully parked before the
    /// release is scheduled. Nothing then makes progress.
    ///
    /// Dispatch grows its own pool past a blocked worker, so running the
    /// blocking body there keeps the returned task suspended rather than
    /// parked, and the release always gets a thread.
    ///
    /// - Parameter work: Synchronous work that may block its thread.
    /// - Returns: A task that completes with `work`'s result.
    func blockingTask<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) -> Task<Value, Never> {
        Task {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: work())
                }
            }
        }
    }
#endif
