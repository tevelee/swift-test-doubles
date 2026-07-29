import Testing
@testable import TestDoubles

private final class ReferenceResult: @unchecked Sendable {
    let value: Int

    init(value: Int) {
        self.value = value
    }
}

private protocol ReferenceResultProbe {
    func load() -> ReferenceResult
    func loadAsync() async -> ReferenceResult
    func optional() -> ReferenceResult?
}

private protocol ResultMarker: AnyObject {
    var value: Int { get }
}

extension ReferenceResult: ResultMarker {}

private protocol ExistentialResultProbe {
    func load() -> any ResultMarker
}

@Suite struct RecordingReturnPlaceholderTests {
    @Test func referenceResultPlaceholderSupportsStubbingAndVerification() throws {
        let stub = try makeReferenceResultStub()
        let placeholder = ReferenceResult(value: -1)
        let configured = ReferenceResult(value: 42)

        stub.when(returning: placeholder) { $0.load() }.thenReturn(configured)

        let result = stub().load()
        #expect(result === configured)
        stub.verify(.exactly(1), returning: placeholder) { $0.load() }
    }

    @Test func asyncReferenceResultPlaceholderSupportsStubbingAndVerification() async throws {
        let stub = try makeReferenceResultStub()
        let placeholder = ReferenceResult(value: -1)
        let configured = ReferenceResult(value: 42)

        await stub.when(returning: placeholder) { await $0.loadAsync() }
            .thenReturn(configured)

        let result = await stub().loadAsync()
        #expect(result === configured)
        await stub.verify(.exactly(1), returning: placeholder) {
            await $0.loadAsync()
        }
    }

    @Test func nilOptionalIsDistinctFromNoResultPlaceholder() throws {
        let stub = try makeReferenceResultStub()
        let placeholder: ReferenceResult? = nil
        let configured = ReferenceResult(value: 42)

        stub.when(returning: placeholder) { $0.optional() }.thenReturn(configured)

        #expect(stub().optional() === configured)
        stub.verify(returning: placeholder) { $0.optional() }
    }

    @Test func existentialResultPlaceholderPreservesDynamicValue() throws {
        let stub = try Stub<any ExistentialResultProbe>(
            .method(returning: (any ResultMarker).self)
        )
        let placeholder: any ResultMarker = ReferenceResult(value: -1)
        let configured = ReferenceResult(value: 42)

        stub.when(returning: placeholder) { $0.load() }.thenReturn(configured)

        let result = stub().load()
        #expect(result === configured)
        stub.verify(returning: placeholder) { $0.load() }
    }
}

private func makeReferenceResultStub() throws -> Stub<any ReferenceResultProbe> {
    try Stub(
        .method(returning: ReferenceResult.self),
        .method(returning: ReferenceResult.self, isAsync: true),
        .method(returning: Optional<ReferenceResult>.self)
    )
}
