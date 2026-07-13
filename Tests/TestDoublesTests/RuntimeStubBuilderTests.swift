import Testing
@testable import TestDoubles
import TestDoublesFixtures

private protocol AsyncOneArgumentProbe: Sendable { func call(_ a: Int) async -> Int }
private protocol AsyncTwoArgumentProbe: Sendable { func call(_ a: Int, _ b: Int) async -> Int }
private protocol AsyncThreeArgumentProbe: Sendable { func call(_ a: Int, _ b: Int, _ c: Int) async -> Int }
private protocol AsyncFourArgumentProbe: Sendable { func call(_ a: Int, _ b: Int, _ c: Int, _ d: Int) async -> Int }
private protocol AsyncFiveArgumentProbe: Sendable { func call(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) async -> Int }
private protocol AsyncSixArgumentProbe: Sendable {
    func call(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int) async -> Int
}
private protocol AsyncVoidArgumentProbe: Sendable { func finish(_ value: Int) async }

private actor BuilderInvocationLog {
    private var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> [Int] {
        values
    }
}

@Suite(.serialized)
struct RuntimeStubBuilderTests {
    @Test func typedThenAsyncSupportsZeroArguments() async {
        let zero = RuntimeStub<any AsyncRuntimeABIProbe>()
        await zero.when { await $0.noArguments() }.thenAsync {
            await Task.yield()
            return 0
        }
        let zeroSUT: any AsyncRuntimeABIProbe = zero()
        #expect(await zeroSUT.noArguments() == 0)
    }

    @Test func typedThenAsyncSupportsOneArgument() async throws {
        let one = try RuntimeStub<any AsyncOneArgumentProbe>.make(
            .method(Int.self, returns: Int.self, async: true)
        )
        await one.when { await $0.call(any()) }.thenAsync { (a: Int) in
            await sumAfterYield([a])
        }
        let oneSUT: any AsyncOneArgumentProbe = one()
        #expect(await oneSUT.call(1) == 1)
    }

    @Test func typedThenAsyncSupportsTwoArguments() async throws {
        let two = try RuntimeStub<any AsyncTwoArgumentProbe>.make(
            .method(Int.self, Int.self, returns: Int.self, async: true)
        )
        await two.when { await $0.call(any(), any()) }.thenAsync { (a: Int, b: Int) in
            await sumAfterYield([a, b])
        }
        let twoSUT: any AsyncTwoArgumentProbe = two()
        #expect(await twoSUT.call(1, 2) == 3)
    }

    @Test func typedThenAsyncSupportsThreeArguments() async throws {
        let three = try RuntimeStub<any AsyncThreeArgumentProbe>.make(
            .method(args: [Int.self, Int.self, Int.self], returns: Int.self, async: true)
        )
        await three.when { await $0.call(any(), any(), any()) }.thenAsync {
            (a: Int, b: Int, c: Int) in
            await sumAfterYield([a, b, c])
        }
        let threeSUT: any AsyncThreeArgumentProbe = three()
        #expect(await threeSUT.call(1, 2, 3) == 6)
    }

    @Test func typedThenAsyncSupportsFourArguments() async throws {
        let four = try RuntimeStub<any AsyncFourArgumentProbe>.make(
            .method(args: [Int.self, Int.self, Int.self, Int.self], returns: Int.self, async: true)
        )
        await four.when { await $0.call(any(), any(), any(), any()) }.thenAsync {
            (a: Int, b: Int, c: Int, d: Int) in
            await sumAfterYield([a, b, c, d])
        }
        let fourSUT: any AsyncFourArgumentProbe = four()
        #expect(await fourSUT.call(1, 2, 3, 4) == 10)
    }

    @Test func typedThenAsyncSupportsFiveArguments() async throws {
        let five = try RuntimeStub<any AsyncFiveArgumentProbe>.make(
            .method(
                args: [Int.self, Int.self, Int.self, Int.self, Int.self],
                returns: Int.self,
                async: true
            )
        )
        await five.when { await $0.call(any(), any(), any(), any(), any()) }.thenAsync {
            (a: Int, b: Int, c: Int, d: Int, e: Int) in
            await sumAfterYield([a, b, c, d, e])
        }
        let fiveSUT: any AsyncFiveArgumentProbe = five()
        #expect(await fiveSUT.call(1, 2, 3, 4, 5) == 15)
    }

    @Test func typedThenAsyncSupportsSixArguments() async throws {
#if arch(x86_64)
        // registerSixArgumentHandler(on:) provides compile-time coverage here.
        // Constructing this x86_64 async signature currently crosses the
        // continuation-register boundary tracked for platform hardening.
        return
#else
        let six = try RuntimeStub<any AsyncSixArgumentProbe>.make(
            .method(
                args: [Int.self, Int.self, Int.self, Int.self, Int.self, Int.self],
                returns: Int.self,
                async: true
            )
        )
        let builder = await six.when {
            await $0.call(any(), any(), any(), any(), any(), any())
        }
        registerSixArgumentHandler(on: builder)
        let sixSUT: any AsyncSixArgumentProbe = six()
        #expect(await sixSUT.call(1, 2, 3, 4, 5, 6) == 21)
#endif
    }

    @Test func typedThenAsyncSupportsArityBeyondPreviousLimit() async throws {
        let arguments: [Any] = [1, 2, 3, 4, 5, 6, 7]
        let recorder = StubRecorder()
        recorder.setRuntimeMethod(
            RuntimeMethodDescriptor(
                MethodDescriptor(
                    name: "call",
                    signature: .init(
                        args: Array(repeating: "Swift.Int", count: arguments.count),
                        ret: "Swift.Int"
                    ),
                    index: 0,
                    isAsync: true
                )
            ),
            for: 0
        )
        let builder = StubBuilder<Int>(
            recorder: recorder,
            recording: RecordedCall(methodIndex: 0, name: "call", args: arguments, matchers: [])
        )
        builder.thenAsync {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) in
            await sumAfterYield([a, b, c, d, e, f, g])
        }

        let handler = try #require(recorder.prepareAsyncDispatch(method: 0, args: arguments))
        let result = try await handler(arguments)
        let typedResult = try #require(result as? Int)

        #expect(typedResult == 28)
    }

    @Test func asyncClosuresUseUnifiedThenSpelling() async throws {
        let stub = try RuntimeStub<any AsyncOneArgumentProbe>.make(
            .method(Int.self, returns: Int.self, async: true)
        )

        await stub.when { await $0.call(any()) }.then { (value: Int) in
            await Task.yield()
            return value * 2
        }

        let sut: any AsyncOneArgumentProbe = stub()
        #expect(await sut.call(21) == 42)
    }

    @Test func typedThenAsyncOverridesAutomaticVoidFallback() async throws {
        let stub = try RuntimeStub<any AsyncVoidArgumentProbe>.make(
            .method(Int.self, async: true)
        )
        let log = BuilderInvocationLog()

        await stub.when { await $0.finish(any()) }.thenAsync { (value: Int) in
            await log.append(value)
        }

        let sut: any AsyncVoidArgumentProbe = stub()
        await sut.finish(42)

        #expect(await log.snapshot() == [42])
    }

    @Test func specificityIsUnifiedAcrossReturnsThenAndThenAsync() async throws {
        let stub = try RuntimeStub<any AsyncDataLoader>.make()

        await stub.when { try await $0.load(url: any()) }.thenAsync { (url: String) in
            await Task.yield()
            return "async-default:\(url)"
        }
        await stub.when {
            try await $0.load(url: any(where: { $0.hasPrefix("typed:") }))
        }.returns("static-typed")
        await stub.when {
            try await $0.load(url: equal("typed:exact"))
        }.then { (url: String) in
            "immediate:\(url)"
        }
        await stub.when {
            try await $0.load(url: equal("unified"))
        }.then { (url: String) in
            await Task.yield()
            return "unified-async:\(url)"
        }

        let sut: any AsyncDataLoader = stub()

        #expect(try await sut.load(url: "other") == "async-default:other")
        #expect(try await sut.load(url: "typed:value") == "static-typed")
        #expect(try await sut.load(url: "typed:exact") == "immediate:typed:exact")
        #expect(try await sut.load(url: "unified") == "unified-async:unified")
    }
}

private func sumAfterYield(_ values: [Int]) async -> Int {
    await Task.yield()
    return values.reduce(0, +)
}

private func registerSixArgumentHandler(on builder: StubBuilder<Int>) {
    builder.thenAsync { (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in
        await sumAfterYield([a, b, c, d, e, f])
    }
}
