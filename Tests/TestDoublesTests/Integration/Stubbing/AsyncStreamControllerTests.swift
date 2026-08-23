@testable import TestDoubles
import Testing

private protocol ManualEventStreamSource {
    func events() -> AsyncStream<Int>
}

private struct ManualEventStreamSourceStub: ManualEventStreamSource, ManualStubConformer {
    let stub: ManualStub<Self>

    func events() -> AsyncStream<Int> {
        stub.call()
    }
}

struct AsyncStreamControllerTests {
    @Test func `manual stubs use the same stream controller API`() async {
        let stub = ManualStub<ManualEventStreamSourceStub>()
        let calls = stub.whenStream { $0.events() }
        let controller = calls.thenStream()
        var iterator = stub().events().makeAsyncIterator()

        controller.yield(21)
        #expect(await iterator.next() == 21)
        controller.finish()
        #expect(await iterator.next() == nil)
        calls.verify()
    }
}
