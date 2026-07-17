import Testing
@testable import TestDoubles

private protocol HandlerArityProbe: Sendable {
    func zero() -> Int
    func one(_ a: Int) -> Int
    func two(_ a: Int, _ b: Int) -> Int
    func three(_ a: Int, _ b: Int, _ c: Int) -> Int
    func four(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Int
    func five(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) -> Int
    func six(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int) -> Int
    func seven(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int) -> Int
    func throwing(_ value: Int) throws -> Int
    func asynchronous(_ value: Int) async -> Int
    func asyncThrowing(_ value: Int) async throws -> Int
}

private struct HandlerError: Error, Equatable {
    let value: Int
}

@Suite struct StubBuilderTests {
    @Test func typedThenSupportsZeroThroughSevenArguments() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.zero() }.then { 0 }
        stub.when { $0.one(any()) }.then { (a: Int) in a }
        stub.when { $0.two(any(), any()) }.then { (a: Int, b: Int) in a + b }
        stub.when { $0.three(any(), any(), any()) }.then {
            (a: Int, b: Int, c: Int) in a + b + c
        }
        stub.when { $0.four(any(), any(), any(), any()) }.then {
            (a: Int, b: Int, c: Int, d: Int) in a + b + c + d
        }
        stub.when { $0.five(any(), any(), any(), any(), any()) }.then {
            (a: Int, b: Int, c: Int, d: Int, e: Int) in a + b + c + d + e
        }
        stub.when { $0.six(any(), any(), any(), any(), any(), any()) }.then {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in
            a + b + c + d + e + f
        }
        stub.when { $0.seven(any(), any(), any(), any(), any(), any(), any()) }.then {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) in
            a + b + c + d + e + f + g
        }

        let probe: any HandlerArityProbe = stub(sendability: .unchecked)
        #expect(probe.zero() == 0)
        #expect(probe.one(1) == 1)
        #expect(probe.two(1, 2) == 3)
        #expect(probe.three(1, 2, 3) == 6)
        #expect(probe.four(1, 2, 3, 4) == 10)
        #expect(probe.five(1, 2, 3, 4, 5) == 15)
        #expect(probe.six(1, 2, 3, 4, 5, 6) == 21)
        #expect(probe.seven(1, 2, 3, 4, 5, 6, 7) == 28)
    }

    @Test func unifiedThenSupportsThrowingAsyncAndAsyncThrowingHandlers() async throws {
        let stub = try makeHandlerArityStub()
        stub.when { try $0.throwing(any()) }.then { (value: Int) throws in
            if value < 0 { throw HandlerError(value: value) }
            return value * 2
        }
        await stub.when { await $0.asynchronous(any()) }.then {
            (value: Int) async throws -> Int in
            await Task.yield()
            return value + 1
        }
        await stub.when { try await $0.asyncThrowing(any()) }.then {
            (value: Int) async throws -> Int in
            await Task.yield()
            if value < 0 { throw HandlerError(value: value) }
            return value + 2
        }

        let probe: any HandlerArityProbe = stub(sendability: .unchecked)
        #expect(try probe.throwing(21) == 42)
        #expect(throws: HandlerError.self) { try probe.throwing(-1) }
        #expect(await probe.asynchronous(41) == 42)
        #expect(try await probe.asyncThrowing(40) == 42)
        await #expect(throws: HandlerError.self) {
            try await probe.asyncThrowing(-2)
        }
    }

    @Test func thenReturnSequenceServesConsecutiveValuesAndRepeatsTheLast() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(any()) }.thenReturn(1, 2, 3)

        let probe: any HandlerArityProbe = stub(sendability: .unchecked)
        #expect(probe.one(0) == 1)
        #expect(probe.one(0) == 2)
        #expect(probe.one(0) == 3)
        #expect(probe.one(0) == 3)
    }

    @Test func thenReturnSequenceServesAsyncRequirements() async throws {
        let stub = try makeHandlerArityStub()
        await stub.when { try await $0.asyncThrowing(any()) }.thenReturn(1, 2)

        let probe: any HandlerArityProbe = stub(sendability: .unchecked)
        #expect(try await probe.asyncThrowing(0) == 1)
        #expect(try await probe.asyncThrowing(0) == 2)
        #expect(try await probe.asyncThrowing(0) == 2)
    }

    @Test func thenReturnSequencesAdvanceIndependentlyPerRegistration() throws {
        let stub = try makeHandlerArityStub()
        stub.when { $0.one(any()) }.thenReturn(1, 2)
        stub.when { $0.one(equal(9)) }.thenReturn(90, 91)

        let probe: any HandlerArityProbe = stub(sendability: .unchecked)
        #expect(probe.one(0) == 1)
        #expect(probe.one(9) == 90)
        #expect(probe.one(0) == 2)
        #expect(probe.one(9) == 91)
        #expect(probe.one(0) == 2)
        #expect(probe.one(9) == 91)
    }

    @Test func thenReturnAndThenShareSpecificityRules() async throws {
        let stub = try makeHandlerArityStub()
        await stub.when { try await $0.asyncThrowing(any()) }.then {
            (value: Int) async throws -> Int in value
        }
        await stub.when {
            try await $0.asyncThrowing(
                matching(description: "positive", where: { $0 > 0 })
            )
        }.thenReturn(10)
        await stub.when { try await $0.asyncThrowing(equal(42)) }.then {
            (_: Int) async throws -> Int in 100
        }

        let probe: any HandlerArityProbe = stub(sendability: .unchecked)
        #expect(try await probe.asyncThrowing(-1) == -1)
        #expect(try await probe.asyncThrowing(1) == 10)
        #expect(try await probe.asyncThrowing(42) == 100)
    }
}

private func makeHandlerArityStub() throws -> Stub<any HandlerArityProbe> {
    try Stub<any HandlerArityProbe>(
        .method(returning: Int.self),
        .method(Int.self, returning: Int.self),
        .method(Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, Int.self, Int.self, Int.self, Int.self, Int.self, Int.self, returning: Int.self),
        .method(Int.self, returning: Int.self, isThrowing: true),
        .method(Int.self, returning: Int.self, isAsync: true),
        .method(Int.self, returning: Int.self, isThrowing: true, isAsync: true)
    )
}
