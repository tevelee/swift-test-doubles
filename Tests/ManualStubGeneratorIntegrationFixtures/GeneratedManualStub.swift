import TestDoubles

struct GeneratedManualStubServiceStubConformer: GeneratedManualStubService, ManualStubConformer {
    let stub: ManualStub<Self>

    init(stub: ManualStub<Self>) { self.stub = stub }

    func render(_ value: Int) -> String { stub.call(value) }

    func render(_ value: String) -> String { stub.call(value) }

    func save(_ value: Int) throws(GeneratedManualStubFailure) { try stub.throwingCall(value, throwing: GeneratedManualStubFailure.self) }

    func refresh(_ value: Int) async throws(GeneratedManualStubFailure) -> String { try await stub.throwingCall(value, throwing: GeneratedManualStubFailure.self) }

    var count: Int {
        get { stub.call() }
        set { stub.call(newValue) }
    }

    subscript(_ value: Int) -> String {
        get { stub.call(value) }
        set { stub.call(value, newValue) }
    }
}

typealias GeneratedManualStubServiceStub = ManualStub<GeneratedManualStubServiceStubConformer>
