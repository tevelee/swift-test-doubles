import TestDoubles

struct GeneratedManualStubServiceManualStub: GeneratedManualStubService, StubConformer {
    let stub: ManualStub<Self>

    init(stub: ManualStub<Self>) { self.stub = stub }

    private static func manualStubArgumentType<Value>(of _: Value) -> Value.Type { Value.self }

    func render(_ value: Int) -> String { return stub.call(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value))) }

    func render(_ value: String) -> String { return stub.call(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value))) }

    func save(_ value: Int) throws(GeneratedManualStubFailure) { try stub.throwingCall(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value)), throwing: GeneratedManualStubFailure.self) }

    func refresh(_ value: Int) async throws(GeneratedManualStubFailure) -> String {
        return try await stub.asyncThrowingCall(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value)), throwing: GeneratedManualStubFailure.self)
    }

    var count: Int {
        get { return stub.call() }
        set { stub.call(newValue, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: newValue))) }
    }

    subscript(_ value: Int) -> String {
        get { return stub.call(value, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value))) }
        set { stub.call(value, newValue, route: ManualRouteID(argumentTypes: Self.manualStubArgumentType(of: value), Self.manualStubArgumentType(of: newValue))) }
    }
}
