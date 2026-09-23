import Foundation
#if canImport(FoundationNetworking) && !os(Android)
    import FoundationNetworking
#endif
import Testing
import TestDoubles

private enum CheckoutOutcome: Equatable, Sendable {
    case approved(transactionID: String)
    case declined(reason: String)
}

private protocol CheckoutGateway {
    func charge(_ cents: Int) async throws -> CheckoutOutcome
    #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
        func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    #endif
    func load(_ url: URL, completion: @escaping (Result<Data, any Error>) -> Void)
    func run(_ work: @escaping @Sendable () async -> Void) async
    func format(_ date: Date, style: DateFormatter.Style) -> String
}

private struct CheckoutGatewayStubConformer: CheckoutGateway, ManualStubConformer {
    let stub: CompiledStub<Self>

    func charge(_ cents: Int) async throws -> CheckoutOutcome {
        try await stub.throwingCall(cents)
    }

    #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
        func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try await stub.throwingCall(request)
        }
    #endif

    func load(_ url: URL, completion: @escaping (Result<Data, any Error>) -> Void) {
        stub.call(url, completion)
    }

    func run(_ work: @escaping @Sendable () async -> Void) async {
        await stub.call(work)
    }

    func format(_ date: Date, style: DateFormatter.Style) -> String {
        stub.call(date, style)
    }
}

protocol CallbackLoader {
    func load(_ path: String, completion: @escaping (Result<Int, any Error>) -> Void)
    func perform(_ work: @escaping @Sendable () -> Void)
}

struct LiveCallbackLoader: CallbackLoader {
    func load(_ path: String, completion: @escaping (Result<Int, any Error>) -> Void) {}
    func perform(_ work: @escaping @Sendable () -> Void) {}
}

private struct CheckoutClient: Sendable {
    var charge: @Sendable (Int) async throws -> CheckoutOutcome
}

/// Recording synthesizes placeholders for results and arguments that only
/// dummy-grade synthesis can build: payload-only enums, tuples containing
/// response classes, and function values.
@Suite struct RecordingPlaceholderFallbackTests {
    @Test func payloadOnlyEnumResultsNeedNoRegisteredPlaceholder() async throws {
        let gateway = CompiledStub<CheckoutGatewayStubConformer>()
        await gateway.when { try await $0.charge(Match.greaterThan(100)) }
            .thenReturn(.declined(reason: "limit"))
        await gateway.when { try await $0.charge(Match.any()) }
            .thenReturn(.approved(transactionID: "tx-1"))

        let service: any CheckoutGateway = gateway()
        #expect(try await service.charge(50) == .approved(transactionID: "tx-1"))
        #expect(try await service.charge(500) == .declined(reason: "limit"))
    }

    @Test func clientEndpointsRecordPayloadOnlyEnumResults() async throws {
        let client = ClientStub<CheckoutClient> { endpoints in
            CheckoutClient(charge: endpoints.asyncThrowingFunction("charge"))
        }
        await client.when { try await $0.charge(Match.any()) }
            .thenReturn(.approved(transactionID: "tx-2"))

        #expect(try await client().charge(1) == .approved(transactionID: "tx-2"))
    }

    #if canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))
        @Test func dataAndResponseTupleResultsNeedNoRegisteredPlaceholder() async throws {
            let gateway = CompiledStub<CheckoutGatewayStubConformer>()
            let url = URL(string: "https://example.com/users")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            await gateway.when { try await $0.response(for: Match.any()) }
                .thenReturn((Data("[]".utf8), response))

            let (data, received) = try await gateway().response(for: URLRequest(url: url))
            #expect(data == Data("[]".utf8))
            #expect(received.statusCode == 201)
        }
    #endif

    @Test func completionHandlersMatchWithAnyAndReachTheHandler() {
        let gateway = CompiledStub<CheckoutGatewayStubConformer>()
        gateway.when { $0.load(Match.any(), completion: Match.any()) }
            .then { (_: URL, completion: @escaping (Result<Data, any Error>) -> Void) in
                completion(.success(Data([1, 2, 3])))
            }

        let received = LockedValue<Data?>(nil)
        gateway().load(URL(string: "https://example.com/a.png")!) { result in
            received.set(try? result.get())
        }

        #expect(received.value == Data([1, 2, 3]))
        gateway.verify { $0.load(Match.any(), completion: Match.any()) }
    }

    @Test func runtimeStubsMatchCallbackArgumentsWithAny() throws {
        let loader = try Stub<any CallbackLoader>(discoveringFrom: LiveCallbackLoader())
        loader.when { $0.load(Match.any(), completion: Match.any()) }
            .then { (path: String, completion: @escaping (Result<Int, any Error>) -> Void) in
                completion(.success(path.count))
            }
        loader.when { $0.perform(Match.any()) }
            .then { (work: @escaping @Sendable () -> Void) in work() }

        let received = LockedValue<Int?>(nil)
        loader().load("four") { result in received.set(try? result.get()) }
        let performed = LockedValue(false)
        loader().perform { performed.set(true) }

        #expect(received.value == 4)
        #expect(performed.value)
        loader.verify { $0.load(Match.equal("four"), completion: Match.any()) }
    }

    @Test func importedEnumLiteralsMatchByValue() {
        let gateway = CompiledStub<CheckoutGatewayStubConformer>()
        gateway.when { $0.format(Match.any(), style: .short) }.thenReturn("short")
        gateway.when { $0.format(Match.any(), style: Match.any()) }.thenReturn("other")

        #expect(gateway().format(Date(), style: .short) == "short")
        #expect(gateway().format(Date(), style: .long) == "other")
        gateway.verify { $0.format(Match.any(), style: .short) }
    }

    @Test func asyncClosureArgumentsMatchWithAny() async {
        let gateway = CompiledStub<CheckoutGatewayStubConformer>()
        await gateway.when { await $0.run(Match.any()) }
            .then { (work: @escaping @Sendable () async -> Void) in await work() }

        let ran = LockedValue(false)
        await gateway().run { ran.set(true) }

        #expect(ran.value)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func set(_ value: Value) {
        lock.withLock { stored = value }
    }
}
