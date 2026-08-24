import ConsumerFixtures
import TestDoubles
import Testing

#if !os(Linux)
    // Swift 6.3.3's Linux frontend crashes in LoadableByAddress while
    // IR-generating this source. macOS CI still exercises this external
    // consumer path; Linux retains the rest of the consumer suite.
    private struct ExpectedStreamFailure: Error, Equatable {}

    private func makeEventStreamStub() throws -> Stub<any EventStreamSource> {
        let integersAdapter:
            @convention(thin) (
                Stub<any EventStreamSource>.Invocation,
            ) -> AsyncStream<Int> = { invocation in
                invocation.call()
            }
        let labelsAdapter:
            @convention(thin) (
                Stub<any EventStreamSource>.Invocation,
            ) -> AsyncThrowingStream<String, any Error> = { invocation in
                invocation.call()
            }
        return try Stub<any EventStreamSource>(
            .method(returning: AsyncStream<Int>.self, using: integersAdapter),
            .method(
                returning: AsyncThrowingStream<String, any Error>.self,
                using: labelsAdapter,
            ),
        )
    }

    struct AsyncStreamControllerConsumerTests {
        @Test func `controller delivers values in order and finishes`() async throws {
            let stub = try makeEventStreamStub()
            let calls = stub.whenStream { $0.integers() }
            let controller = calls.thenStream()
            let source = stub()
            let values = Task { () -> [Int] in
                var received: [Int] = []
                for await value in source.integers() {
                    received.append(value)
                }
                return received
            }

            controller.yield(2)
            controller.yield(3)
            controller.finish()

            #expect(await values.value == [2, 3])
            #expect(controller.termination == .finished)
            calls.verify()
        }

        @Test func `throwing controller propagates its error`() async throws {
            let stub = try makeEventStreamStub()
            let controller = stub.whenThrowingStream { $0.labels() }.thenThrowingStream()
            var iterator = stub().labels().makeAsyncIterator()

            controller.yield("ready")
            #expect(try await iterator.next() == "ready")
            controller.finish(throwing: ExpectedStreamFailure())
            await #expect(throws: ExpectedStreamFailure.self) {
                _ = try await iterator.next()
            }
            #expect(controller.termination == .finished)
        }

        @Test func `controller honors its buffering policy`() async throws {
            let stub = try makeEventStreamStub()
            let controller = stub.whenStream { $0.integers() }
                .thenStream(bufferingPolicy: .bufferingNewest(1))
            let stream = stub().integers()

            controller.yield(5)
            controller.yield(8)
            controller.finish()

            var iterator = stream.makeAsyncIterator()
            #expect(await iterator.next() == 8)
            #expect(await iterator.next() == nil)
        }

        @Test func `cancelling A consumer terminates its controller`() async throws {
            let stub = try makeEventStreamStub()
            let controller = stub.whenStream { $0.integers() }.thenStream()
            let source = stub()
            let consumer = Task {
                for await _ in source.integers() {}
            }

            await Task.yield()
            consumer.cancel()
            await consumer.value

            #expect(controller.termination == .cancelled)
        }

        @Test func `yielding after finish reports termination`() {
            let controller = AsyncStreamController<Int>()
            controller.finish()

            switch controller.yield(13) {
                case .terminated:
                    break
                case .dropped, .enqueued:
                    Issue.record("Expected a finished controller to reject later values.")
                @unknown default:
                    Issue.record("Expected a finished controller to report termination.")
            }
        }
    }
#endif
