import Testing
@testable import TestDoubles
import TestDoublesFixtures

private struct AsyncHandlerError: Error, Equatable {
    let url: String
}

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

private protocol CompositionA {}
private protocol CompositionB {}

@Suite struct ConstructionErrorTests {
    @Test func automaticConstructionRequiresLinkedConformance() {
        do {
            _ = try Stub<any PrototypeCalculator>()
            Issue.record("Expected a missing-conformance error")
        } catch let error as StubError {
            guard case .noConformanceFound(let protocolName) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "PrototypeCalculator")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func rejectsWrongRequirementCount() {
        do {
            _ = try Stub<any PrototypeCalculator>(
                .method(Int.self, Int.self, returning: Int.self)
            )
            Issue.record("Expected a requirement-count error")
        } catch let error as StubError {
            guard case .requirementCountMismatch(let protocolName, let expected, let actual) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "PrototypeCalculator")
            #expect(expected == 3)
            #expect(actual == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func rejectsWrongRequirementKind() {
        do {
            _ = try Stub<any PrototypeCalculator>(
                .getter(Int.self),
                .method(Int.self, returning: String.self),
                .getter(Int.self)
            )
            Issue.record("Expected a requirement-kind error")
        } catch let error as StubError {
            guard case .requirementKindMismatch(
                let protocolName, let index, let expected, let actual
            ) = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
            #expect(protocolName == "PrototypeCalculator")
            #expect(index == 0)
            #expect(expected == "method")
            #expect(actual == "getter")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func rejectsNonProtocolTypes() {
        do {
            _ = try Stub<Int>()
            Issue.record("Expected a non-protocol error")
        } catch let error as StubError {
            guard case .typeIsNotProtocol = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func rejectsProtocolCompositions() {
        do {
            _ = try Stub<any CompositionA & CompositionB>()
            Issue.record("Expected a protocol-composition error")
        } catch let error as StubError {
            guard case .unsupportedProtocolComposition = error else {
                Issue.record("Unexpected StubError: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite struct AsyncUsabilityTests {
    @Test func automaticAsyncConstructionAndDirectVerification() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }.returns("runtime-data")
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(3)

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "https://example.com") == "runtime-data")
        await loader.prefetch(urls: ["one", "two"])
        #expect(loader.cacheSize == 3)

        await stub.verify { try await $0.load(url: any()) }
        await stub.verify(.exactly(1)) { await $0.prefetch(urls: any()) }
    }

    @Test func suspendingAsyncThrowingHandlerPropagatesValuesAndErrors() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: equal("success")) }.then {
            () async throws -> String in
            await Task.yield()
            return "loaded"
        }
        await stub.when { try await $0.load(url: any()) }.then {
            (url: String) async throws -> String in
            await Task.yield()
            throw AsyncHandlerError(url: url)
        }

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "success") == "loaded")
        let error = await #expect(throws: AsyncHandlerError.self) {
            try await loader.load(url: "missing")
        }
        #expect(error?.url == "missing")
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
