import Testing
@testable import TestDoubles

private final class ManualSession: Sendable {
    let id: Int
    init(id: Int) { self.id = id }
}

private protocol ManualOverloadService {
    func makeSession() -> ManualSession
    func acquire() async -> ManualSession
    func purge() async throws
    func flush() throws -> Int
    func labelFor(_ id: Int) -> String
    func clear()
    func code() throws -> Int
    func commit() throws
    func warmup() async
    func syncUp() async throws
    var count: Int { get set }
}

private protocol ManualTrueOverloadService {
    func status() -> Int
    func status() async -> Int
    func decoded() -> Int
    func decoded() -> String
}

private protocol ManualTypedRouteService {
    func render(_ value: Int) -> String
    func render(_ value: String) -> String
    func consume(_ value: Int)
    func throwingValue(_ value: Int) throws -> String
    func throwingEffect(_ value: Int) throws
    func asyncValue(_ value: Int) async -> String
    func asyncEffect(_ value: Int) async
    func asyncThrowingValue(_ value: Int) async throws -> String
    func asyncThrowingEffect(_ value: Int) async throws
}

private struct ManualOverloadServiceStub: ManualOverloadService, StubConformer {
    let stub: ManualStub<Self>

    func makeSession() -> ManualSession { stub.makeSession() }
    func acquire() async -> ManualSession { await stub.acquire() }
    func purge() async throws { try await stub.throwing.purge() }
    func flush() throws -> Int { try stub.throwing.flush() }
    func labelFor(_ id: Int) -> String { stub.call(id) }
    func clear() { stub.call() }
    func code() throws -> Int { try stub.throwingCall() }
    func commit() throws { try stub.throwingCall() }
    func warmup() async { await stub.asyncCall() }
    func syncUp() async throws { try await stub.asyncThrowingCall() }
    var count: Int {
        get { stub.count }
        set { stub.count = newValue }
    }
}

private struct ManualTrueOverloadServiceStub: ManualTrueOverloadService, StubConformer {
    let stub: ManualStub<Self>

    func status() -> Int { stub.status() }
    func status() async -> Int { await stub.status() }
    func decoded() -> Int { stub.decoded() }
    func decoded() -> String { stub.decoded() }
}

private struct ManualTypedRouteServiceStub: ManualTypedRouteService, StubConformer {
    let stub: ManualStub<Self>

    func render(_ value: Int) -> String {
        stub.call(value, route: ManualRouteID(argumentTypes: Int.self))
    }

    func render(_ value: String) -> String {
        stub.call(value, route: ManualRouteID(argumentTypes: String.self))
    }

    func consume(_ value: Int) {
        stub.call(value, route: ManualRouteID(argumentTypes: Int.self))
    }

    func throwingValue(_ value: Int) throws -> String {
        try stub.throwingCall(value, route: ManualRouteID(argumentTypes: Int.self))
    }

    func throwingEffect(_ value: Int) throws {
        try stub.throwingCall(value, route: ManualRouteID(argumentTypes: Int.self))
    }

    func asyncValue(_ value: Int) async -> String {
        await stub.asyncCall(value, route: ManualRouteID(argumentTypes: Int.self))
    }

    func asyncEffect(_ value: Int) async {
        await stub.asyncCall(value, route: ManualRouteID(argumentTypes: Int.self))
    }

    func asyncThrowingValue(_ value: Int) async throws -> String {
        try await stub.asyncThrowingCall(
            value,
            route: ManualRouteID(argumentTypes: Int.self)
        )
    }

    func asyncThrowingEffect(_ value: Int) async throws {
        try await stub.asyncThrowingCall(
            value,
            route: ManualRouteID(argumentTypes: Int.self)
        )
    }
}

private func synchronousStatus(_ service: any ManualTrueOverloadService) -> Int {
    service.status()
}

private struct PurgeError: Error, Equatable {}

@Suite struct ManualStubOverloadTests {
    @Test func typedRouteIdentityIsSeparateFromDiagnosticsAndImplicitRoutes() {
        let recorder = StubRecorder(methods: [])
        let intRoute = ManualRouteID("render(_:)", argumentTypes: Int.self)
        let stringRoute = ManualRouteID("render(_:)", argumentTypes: String.self)

        let typedInt = recorder.internManualMethod(
            route: .typed(intRoute),
            kind: .method,
            returnType: String.self,
            isAsync: false,
            isThrowing: false
        )
        let typedString = recorder.internManualMethod(
            route: .typed(stringRoute),
            kind: .method,
            returnType: String.self,
            isAsync: false,
            isThrowing: false
        )
        let implicit = recorder.internManualMethod(
            signature: "render(_:)",
            kind: .method,
            returnType: String.self,
            isAsync: false,
            isThrowing: false
        )
        let repeatedInt = recorder.internManualMethod(
            route: .typed(intRoute),
            kind: .method,
            returnType: String.self,
            isAsync: false,
            isThrowing: false
        )

        #expect(typedInt.index != typedString.index)
        #expect(typedInt.index != implicit.index)
        #expect(repeatedInt.index == typedInt.index)
        #expect([typedInt.name, typedString.name, implicit.name] == Array(repeating: "render(_:)", count: 3))
    }

    @Test func typedRoutesDistinguishArgumentTypeOverloads() {
        let intFirst = ManualStub<ManualTypedRouteServiceStub>()
        intFirst.when { $0.render(equal(7)) }.thenReturn("integer")
        intFirst.when { $0.render(equal("7")) }.thenReturn("string")

        let service: any ManualTypedRouteService = intFirst()
        #expect(service.render(7) == "integer")
        #expect(service.render("7") == "string")
        intFirst.verify(.exactly(1)) { $0.render(equal(7)) }
        intFirst.verify(.exactly(1)) { $0.render(equal("7")) }

        let stringFirst = ManualStub<ManualTypedRouteServiceStub>()
        stringFirst.when { $0.render(equal("8")) }.thenReturn("string-first")
        stringFirst.when { $0.render(equal(8)) }.thenReturn("integer-second")

        let reverseService: any ManualTypedRouteService = stringFirst()
        #expect(reverseService.render(8) == "integer-second")
        #expect(reverseService.render("8") == "string-first")
    }

    @Test func typedBehaviorsCoverEveryEffectAndResultCombination() async throws {
        let stub = ManualStub<ManualTypedRouteServiceStub>()
        stub.when { $0.consume(equal(1)) }.thenDoNothing()
        stub.when { try $0.throwingValue(equal(2)) }.thenReturn("throwing")
        stub.when { try $0.throwingEffect(equal(3)) }.thenDoNothing()
        await stub.when { await $0.asyncValue(equal(4)) }.thenReturn("async")
        await stub.when { await $0.asyncEffect(equal(5)) }.thenDoNothing()
        await stub.when { try await $0.asyncThrowingValue(equal(6)) }
            .thenReturn("async-throwing")
        await stub.when { try await $0.asyncThrowingEffect(equal(7)) }.thenDoNothing()

        let service: any ManualTypedRouteService = stub()
        service.consume(1)
        #expect(try service.throwingValue(2) == "throwing")
        try service.throwingEffect(3)
        #expect(await service.asyncValue(4) == "async")
        await service.asyncEffect(5)
        #expect(try await service.asyncThrowingValue(6) == "async-throwing")
        try await service.asyncThrowingEffect(7)
    }

    @Test func syncAndAsyncOverloadsHaveIndependentRecorderSlots() async {
        let syncFirst = ManualStub<ManualTrueOverloadServiceStub>()
        syncFirst.when { $0.status() }.thenReturn(1)
        await syncFirst.when { await $0.status() }.thenReturn(2)

        let service: any ManualTrueOverloadService = syncFirst()
        #expect(synchronousStatus(service) == 1)
        #expect(await service.status() == 2)

        syncFirst.verify(.exactly(1)) { $0.status() }
        await syncFirst.verify(.exactly(1)) { await $0.status() }

        let asyncFirst = ManualStub<ManualTrueOverloadServiceStub>()
        await asyncFirst.when { await $0.status() }.thenReturn(4)
        asyncFirst.when { $0.status() }.thenReturn(3)

        let reverseService: any ManualTrueOverloadService = asyncFirst()
        #expect(synchronousStatus(reverseService) == 3)
        #expect(await reverseService.status() == 4)
    }

    @Test func returnTypeOverloadsHaveIndependentRecorderSlots() {
        let stub = ManualStub<ManualTrueOverloadServiceStub>()
        stub.when { service -> Int in service.decoded() }.thenReturn(3)
        stub.when { service -> String in service.decoded() }.thenReturn("three")

        let service: any ManualTrueOverloadService = stub()
        let integer: Int = service.decoded()
        let string: String = service.decoded()
        #expect(integer == 3)
        #expect(string == "three")

        stub.verify(.exactly(1)) { service -> Int in service.decoded() }
        stub.verify(.exactly(1)) { service -> String in service.decoded() }
    }

    @Test func placeholderOverloadsCoverReferenceResults() {
        let stub = ManualStub<ManualOverloadServiceStub>()
        let placeholder = ManualSession(id: -1)
        let real = ManualSession(id: 7)
        stub.when(returning: placeholder) { $0.makeSession() }.thenReturn(real)

        let service: any ManualOverloadService = stub()
        #expect(service.makeSession() === real)
        stub.verify(.exactly(1), returning: placeholder) { $0.makeSession() }
    }

    @Test func asyncPlaceholderOverloadsCoverReferenceResults() async {
        let stub = ManualStub<ManualOverloadServiceStub>()
        let placeholder = ManualSession(id: -1)
        let real = ManualSession(id: 9)
        await stub.when(returning: placeholder) { await $0.acquire() }.thenReturn(real)

        let service: any ManualOverloadService = stub()
        #expect(await service.acquire() === real)
        await stub.verify(.exactly(1), returning: placeholder) { await $0.acquire() }
    }

    @Test func explicitRoutesCoverEveryEffectCombination() async throws {
        let stub = ManualStub<ManualOverloadServiceStub>()
        stub.when { $0.labelFor(equal(3)) }.thenReturn("three")
        stub.when { $0.clear() }.thenDoNothing()
        stub.when { try $0.code() }.thenReturn(200)
        stub.when { try $0.commit() }.thenDoNothing()
        await stub.when { await $0.warmup() }.thenDoNothing()
        await stub.when { try await $0.syncUp() }.thenDoNothing()

        let service: any ManualOverloadService = stub()
        #expect(service.labelFor(3) == "three")
        service.clear()
        #expect(try service.code() == 200)
        try service.commit()
        await service.warmup()
        try await service.syncUp()

        stub.verify(.exactly(1)) { $0.labelFor(any()) }
        stub.verify(.exactly(1)) { $0.clear() }
        stub.verify(.exactly(1)) { try $0.code() }
        stub.verify(.exactly(1)) { try $0.commit() }
        await stub.verify(.exactly(1)) { await $0.warmup() }
        await stub.verify(.exactly(1)) { try await $0.syncUp() }
    }

    @Test func throwingProxiesPropagateValuesAndErrors() async throws {
        let stub = ManualStub<ManualOverloadServiceStub>()
        stub.when { try $0.flush() }.thenReturn(3)
        await stub.when { try await $0.purge() }.then { throw PurgeError() }

        let service: any ManualOverloadService = stub()
        #expect(try service.flush() == 3)
        await #expect(throws: PurgeError.self) {
            try await service.purge()
        }
        await stub.verify(.exactly(1)) { try await $0.purge() }
    }

    @Test func asyncVerifyCountsAndOrderingCoverAsyncRecordings() async {
        let stub = ManualStub<ManualOverloadServiceStub>()
        await stub.when { await $0.warmup() }.thenDoNothing()
        stub.when { $0.clear() }.thenDoNothing()

        let service: any ManualOverloadService = stub()
        await service.warmup()
        service.clear()

        await stub.verify(.never()) { try await $0.syncUp() }
        await stub.verifyInOrder {
            await $0.warmup()
            $0.clear()
        }
    }

    @Test func setterCountVerificationUsesTheInoutOverload() {
        let stub = ManualStub<ManualOverloadServiceStub>()
        stub.when { $0.count = any() }.thenDoNothing()

        var service: any ManualOverloadService = stub()
        service.count = 5

        stub.verify(.exactly(1)) { $0.count = equal(5) }
        stub.verify(.never()) { $0.count = equal(9) }
    }
}
