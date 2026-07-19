import IssueReporting
import Testing
@testable import TestDoubles

protocol EventualVerificationService: Sendable {
    func value(for id: Int) -> String
    func notify(_ value: Int)
    func load(_ id: Int) async -> String
    func makeReference() -> EventualVerificationReference
    var count: Int { get set }
}

final class EventualVerificationReference: @unchecked Sendable {}

struct RealEventualVerificationService: EventualVerificationService {
    func value(for id: Int) -> String { "\(id)" }
    func notify(_ value: Int) {}
    func load(_ id: Int) async -> String { "\(id)" }
    func makeReference() -> EventualVerificationReference { EventualVerificationReference() }
    var count: Int {
        get { 0 }
        set {}
    }
}

protocol ManualEventualVerificationService: Sendable {
    func notify(_ value: Int)
}

struct ManualEventualVerificationServiceStub: ManualEventualVerificationService, StubConformer,
    @unchecked Sendable
{
    let stub: ManualStub<Self>

    func notify(_ value: Int) {
        stub.notify(value)
    }
}

private actor EventualVerificationGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@Suite struct EventualVerificationTests {
    @Test func waitsForALateSynchronousCall() async throws {
        let stub = try Stub<any EventualVerificationService>()
        stub.when { $0.notify(any()) }.thenDoNothing()
        let service: any EventualVerificationService = stub(sendability: .unchecked)

        let invocation = Task {
            try await Task.sleep(for: .milliseconds(10))
            service.notify(42)
        }

        await stub.verify(within: .seconds(10)) { $0.notify(equal(42)) }
        try await invocation.value
    }

    @Test func waitsUntilTheLowerBoundIsReached() async throws {
        let stub = try Stub<any EventualVerificationService>()
        stub.when { $0.notify(any()) }.thenDoNothing()
        let service: any EventualVerificationService = stub(sendability: .unchecked)

        let invocations = Task {
            try await Task.sleep(for: .milliseconds(10))
            service.notify(1)
            service.notify(2)
        }

        await stub.verify(2..., within: .seconds(10)) { $0.notify(any()) }
        try await invocations.value
    }

    @Test func waitsForAnAsyncRequirement() async throws {
        let stub = try Stub<any EventualVerificationService>()
        await stub.when { await $0.load(any()) }.thenReturn("loaded")
        let service: any EventualVerificationService = stub(sendability: .unchecked)

        let invocation = Task {
            try await Task.sleep(for: .milliseconds(10))
            _ = await service.load(7)
        }

        await stub.verify(within: .seconds(10)) { await $0.load(equal(7)) }
        try await invocation.value
    }

    @MainActor
    @Test func timeoutReportsAtTheCallerAndDoesNotRetainItsWaiter() async throws {
        let stub = try Stub<any EventualVerificationService>()
        stub.when { $0.notify(any()) }.thenDoNothing()
        let expectedLine = UInt(#line + 2)
        await expectReportsIssue {
            await stub.verify(within: .milliseconds(1)) { $0.notify(any()) }
        } matching: { issue in
            issue.description.contains("expected at least 1 call within")
                && issue.description.contains("got 0")
                && String(describing: issue.fileID) == String(describing: #fileID)
                && String(describing: issue.filePath) == String(describing: #filePath)
                && issue.line == expectedLine
                && issue.column > 0
        }

        let service: any EventualVerificationService = stub(sendability: .unchecked)
        service.notify(1)
        await stub.verify(within: .seconds(10)) { $0.notify(equal(1)) }
    }

    @Test func manualStubHasEventualVerificationParity() async throws {
        let stub = ManualStub<ManualEventualVerificationServiceStub>()
        stub.when { $0.notify(any()) }.thenDoNothing()
        let service: any ManualEventualVerificationService = stub()

        let invocation = Task {
            try await Task.sleep(for: .milliseconds(10))
            service.notify(9)
        }

        await stub.verify(within: .seconds(10)) { $0.notify(equal(9)) }
        try await invocation.value
    }

    @Test func captorCommitsExactlyOnceAfterThresholdSuccess() async throws {
        let stub = try Stub<any EventualVerificationService>()
        stub.when { $0.notify(any()) }.thenDoNothing()
        let service: any EventualVerificationService = stub(sendability: .unchecked)
        let values = ArgumentCaptor<Int>()

        let invocations = Task {
            try await Task.sleep(for: .milliseconds(10))
            service.notify(1)
            service.notify(2)
        }

        await stub.verify(2..., within: .seconds(10)) {
            $0.notify(values.capture())
        }
        try await invocations.value
        #expect(values.values == [1, 2])
    }

    @MainActor
    @Test func suspendedAsyncCaptureDoesNotCaptureAnotherTasksNormalCall() async throws {
        let stub = try Stub<any EventualVerificationService>()
        stub.when { $0.value(for: any()) }.thenReturn("configured")
        let gate = EventualVerificationGate()

        let configuration = Task { @MainActor in
            await stub.when {
                await gate.suspend()
                return await $0.load(any())
            }.thenReturn("loaded")
        }

        await gate.waitUntilStarted()
        let service: any EventualVerificationService = stub(sendability: .unchecked)
        #expect(service.value(for: 42) == "configured")
        await gate.release()
        _ = await configuration.value

        stub.verify(.exactly(1)) { $0.value(for: equal(42)) }
        await stub.verify(.never()) { await $0.load(any()) }
    }

    @MainActor
    @Test func cancellationRemovesTheWaiterWithoutReporting() async throws {
        let stub = try Stub<any EventualVerificationService>()
        stub.when { $0.notify(any()) }.thenDoNothing()

        let verification = Task { @MainActor in
            await stub.verify(within: .seconds(60)) { $0.notify(any()) }
        }
        await Task.yield()
        verification.cancel()

        await expectReportsIssue {
            await verification.value
            reportIssue("cancellation-completed-quietly")
        } matching: {
            $0.description.contains("cancellation-completed-quietly")
        }

        let service: any EventualVerificationService = stub(sendability: .unchecked)
        service.notify(3)
        await stub.verify(within: .seconds(10)) { $0.notify(equal(3)) }
    }

    @Test func placeholderAndSetterOverloadsWaitForCalls() async throws {
        let stub = try Stub<any EventualVerificationService>()
        let placeholder = EventualVerificationReference()
        stub.when(returning: placeholder) { $0.makeReference() }.thenReturn(placeholder)
        stub.when { $0.count = any() }.thenDoNothing()
        var service: any EventualVerificationService = stub(sendability: .unchecked)

        let invocations = Task {
            try await Task.sleep(for: .milliseconds(10))
            _ = service.makeReference()
            service.count = 4
        }

        await stub.verify(within: .seconds(10), returning: placeholder) {
            $0.makeReference()
        }
        await stub.verify(within: .seconds(10)) { $0.count = equal(4) }
        try await invocations.value
    }
}
