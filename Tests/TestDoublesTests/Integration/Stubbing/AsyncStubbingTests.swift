import Testing
@testable import TestDoubles
import TestDoublesFixtures

private actor SuspensionGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@Suite struct AsyncStubbingTests {
    @Test func automaticAsyncConstructionAndDirectVerification() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }.thenReturn("runtime-data")
        await stub.when { await $0.prefetch(urls: any()) }.thenDoNothing()
        stub.when { $0.cacheSize }.thenReturn(3)

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "https://example.com") == "runtime-data")
        await loader.prefetch(urls: ["one", "two"])
        #expect(loader.cacheSize == 3)

        await stub.verify { try await $0.load(url: any()) }
        await stub.verify(.exactly(1)) { await $0.prefetch(urls: any()) }
    }

    @Test func cancellationReachesSuspendedHandler() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        let gate = SuspensionGate()
        await stub.when { try await $0.load(url: any()) }.then {
            (_: String) async throws -> String in
            await gate.suspend()
            try Task.checkCancellation()
            return "unexpected"
        }

        let task = Task {
            let loader: any AsyncDataLoader = stub()
            return try await loader.load(url: "cancelled")
        }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
