import Testing
import TestDoubles

private enum ManualStubTypedFailure: Error, Equatable {
    case rejected(Int)
}

private struct ManualStubUnexpectedFailure: Error {}

private protocol ManualTypedThrowsService {
    var token: String { get throws(ManualStubTypedFailure) }
    func save(_ value: Int) throws(ManualStubTypedFailure)
    func refresh(_ value: Int) async throws(ManualStubTypedFailure) -> String
    func synchronize(_ value: Int) async throws(ManualStubTypedFailure)

    func routedLoad(_ value: Int) throws(ManualStubTypedFailure) -> String
    func routedReset(_ value: Int) throws(ManualStubTypedFailure)
    func routedRefresh(_ value: Int) async throws(ManualStubTypedFailure) -> String
    func routedSynchronize(_ value: Int) async throws(ManualStubTypedFailure)
}

private struct ManualTypedThrowsServiceStub: ManualTypedThrowsService, StubConformer {
    let stub: ManualStub<Self>

    var token: String {
        get throws(ManualStubTypedFailure) {
            try stub.throwingCall(throwing: ManualStubTypedFailure.self)
        }
    }

    func save(_ value: Int) throws(ManualStubTypedFailure) {
        try stub.throwingCall(
            value,
            throwing: ManualStubTypedFailure.self
        )
    }

    func refresh(_ value: Int) async throws(ManualStubTypedFailure) -> String {
        try await stub.asyncThrowingCall(
            value,
            throwing: ManualStubTypedFailure.self
        )
    }

    func synchronize(_ value: Int) async throws(ManualStubTypedFailure) {
        try await stub.asyncThrowingCall(
            value,
            throwing: ManualStubTypedFailure.self
        )
    }

    func routedLoad(_ value: Int) throws(ManualStubTypedFailure) -> String {
        try stub.throwingCall(
            value,
            route: ManualRouteID(argumentTypes: Int.self),
            throwing: ManualStubTypedFailure.self
        )
    }

    func routedReset(_ value: Int) throws(ManualStubTypedFailure) {
        try stub.throwingCall(
            value,
            route: ManualRouteID(argumentTypes: Int.self),
            throwing: ManualStubTypedFailure.self
        )
    }

    func routedRefresh(_ value: Int) async throws(ManualStubTypedFailure) -> String {
        try await stub.asyncThrowingCall(
            value,
            route: ManualRouteID(argumentTypes: Int.self),
            throwing: ManualStubTypedFailure.self
        )
    }

    func routedSynchronize(_ value: Int) async throws(ManualStubTypedFailure) {
        try await stub.asyncThrowingCall(
            value,
            route: ManualRouteID(argumentTypes: Int.self),
            throwing: ManualStubTypedFailure.self
        )
    }
}

@Suite struct ManualStubTypedThrowsTests {
    @Test func typedGetterAndSyncMethodReturnAndPropagateExactFailures() throws {
        let stub = ManualStub<ManualTypedThrowsServiceStub>()
        stub.when { try $0.token }
            .thenReturn("secret")
            .thenThrow(ManualStubTypedFailure.rejected(1))
        stub.when { try $0.save(equal(2)) }.thenDoNothing()
        stub.when { try $0.save(equal(3)) }
            .thenThrow(ManualStubTypedFailure.rejected(3))

        let service: any ManualTypedThrowsService = stub()
        #expect(try service.token == "secret")
        let getterError = #expect(throws: ManualStubTypedFailure.self) {
            _ = try service.token
        }
        #expect(getterError == .rejected(1))

        try service.save(2)
        let methodError = #expect(throws: ManualStubTypedFailure.self) {
            try service.save(3)
        }
        #expect(methodError == .rejected(3))
    }

    @Test func typedAsyncMethodsReturnAndPropagateExactFailures() async throws {
        let stub = ManualStub<ManualTypedThrowsServiceStub>()
        await stub.when { try await $0.refresh(equal(4)) }.thenReturn("fresh")
        await stub.when { try await $0.refresh(equal(5)) }
            .thenThrow(ManualStubTypedFailure.rejected(5))
        await stub.when { try await $0.synchronize(equal(6)) }.thenDoNothing()
        await stub.when { try await $0.synchronize(equal(7)) }
            .thenThrow(ManualStubTypedFailure.rejected(7))

        let service: any ManualTypedThrowsService = stub()
        #expect(try await service.refresh(4) == "fresh")
        let resultError = await #expect(throws: ManualStubTypedFailure.self) {
            _ = try await service.refresh(5)
        }
        #expect(resultError == .rejected(5))

        try await service.synchronize(6)
        let voidError = await #expect(throws: ManualStubTypedFailure.self) {
            try await service.synchronize(7)
        }
        #expect(voidError == .rejected(7))
    }

    @Test func typedRouteIDsCoverEveryThrowingResultAndEffectCombination() async throws {
        let stub = ManualStub<ManualTypedThrowsServiceStub>()
        stub.when { try $0.routedLoad(equal(8)) }.thenReturn("routed")
        stub.when { try $0.routedReset(equal(9)) }.thenDoNothing()
        await stub.when { try await $0.routedRefresh(equal(10)) }
            .thenReturn("async-routed")
        await stub.when { try await $0.routedSynchronize(equal(11)) }
            .thenDoNothing()

        let service: any ManualTypedThrowsService = stub()
        #expect(try service.routedLoad(8) == "routed")
        try service.routedReset(9)
        #expect(try await service.routedRefresh(10) == "async-routed")
        try await service.routedSynchronize(11)

        stub.verify { try $0.routedLoad(equal(8)) }
        stub.verify { try $0.routedReset(equal(9)) }
        await stub.verify { try await $0.routedRefresh(equal(10)) }
        await stub.verify { try await $0.routedSynchronize(equal(11)) }
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct ManualStubTypedThrowsExitTests {
        @Test
        func mismatchedSynchronousErrorFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = ManualStub<ManualTypedThrowsServiceStub>()
                stub.when { try $0.save(equal(42)) }
                    .thenThrow(ManualStubUnexpectedFailure())
                let service: any ManualTypedThrowsService = stub()
                try service.save(42)
            }
            try assertTypedMismatchDiagnostic(result)
        }

        @Test
        func mismatchedAsynchronousErrorFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = ManualStub<ManualTypedThrowsServiceStub>()
                await stub.when { try await $0.synchronize(equal(42)) }
                    .thenThrow(ManualStubUnexpectedFailure())
                let service: any ManualTypedThrowsService = stub()
                try await service.synchronize(42)
            }
            try assertTypedMismatchDiagnostic(result)
        }

        private func assertTypedMismatchDiagnostic(_ result: ExitTest.Result) throws {
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("Typed ManualStub handler error mismatch"))
            #expect(diagnostic.contains("expected ManualStubTypedFailure"))
            #expect(diagnostic.contains("got ManualStubUnexpectedFailure"))
            #expect(diagnostic.contains("untyped"))
        }
    }
#endif
