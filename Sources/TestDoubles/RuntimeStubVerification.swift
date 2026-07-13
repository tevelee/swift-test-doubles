#if RUNTIME_STUB
extension RuntimeStub {
    /// Verify a method/getter was called.
    public func verify(_ call: (P) -> some Any) -> VerifyBuilder {
        let recording = record(mode: .verifying) { _ = call(self.callAsFunction()) }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Verify a setter was called.
    public func verify(setting call: (inout P) -> Void) -> VerifyBuilder {
        let recording = record(mode: .verifying) {
            var mutable = self.callAsFunction()
            call(&mutable)
        }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Concise verify: `stub.verify(called: 2) { $0.add(1, 2) }` (#5)
    public func verify(called times: Int, _ call: (P) -> some Any) {
        let recording = record(mode: .verifying) { _ = call(self.callAsFunction()) }
        VerifyBuilder(recorder: recorder, recording: recording).wasCalled(times: times)
    }

    /// Concise verify never: `stub.verify(never: { $0.reset() })` (#5)
    public func verify(never call: (P) -> some Any) {
        verify(called: 0, call)
    }

    /// Verify a throwing method/getter was called.
    public func verify(_ call: (P) throws -> some Any) -> VerifyBuilder {
        let recording = record(mode: .verifying) { _ = try! call(self.callAsFunction()) }
        return VerifyBuilder(recorder: recorder, recording: recording)
    }

    /// Concise throwing verify: `stub.verify(called: 2) { try $0.load(path: any()) }`
    public func verify(called times: Int, _ call: (P) throws -> some Any) {
        let recording = record(mode: .verifying) { _ = try! call(self.callAsFunction()) }
        VerifyBuilder(recorder: recorder, recording: recording).wasCalled(times: times)
    }

    /// Concise throwing verify never: `stub.verify(never: { try $0.load(path: any()) })`
    public func verify(never call: (P) throws -> some Any) {
        verify(called: 0, call)
    }

    /// Verify that methods were called in a specific order.
    /// ```swift
    /// stub.verifyOrder {
    ///     $0.find(id: 1)
    ///     $0.save(name: "x", age: 1)
    /// }
    /// ```
    public func verifyOrder(_ calls: (P) -> Void) {
        let expectedOrder = recordOrder(calls).map(\.methodIndex)

        // Find matching calls in original log in order
        var searchFrom = 0
        for (i, expectedMethod) in expectedOrder.enumerated() {
            guard let idx = recorder.calls[searchFrom...].firstIndex(where: { $0.methodIndex == expectedMethod }) else {
                preconditionFailure("verifyOrder: call \(i) (\(recorder.calls.first { $0.methodIndex == expectedMethod }?.name ?? "method_\(expectedMethod)")) not found after position \(searchFrom)")
            }
            searchFrom = idx + 1
        }
    }

    private func recordOrder(_ block: (P) -> Void) -> [RecordedCall] {
        recorder.activeMatchers = []
        recorder.verificationRecordings = []
        _ = MatcherContext.withRecording {
            recorder.mode = .verifying
            block(self.callAsFunction())
        }
        recorder.mode = .normal
        let recordings = recorder.verificationRecordings
        recorder.verificationRecordings = []
        recorder.lastRecording = nil
        guard recordings.isEmpty == false else {
            fatalError("No method was called in the verifyOrder closure")
        }
        return recordings
    }
}
#endif // RUNTIME_STUB
