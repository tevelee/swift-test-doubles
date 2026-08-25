import InternalRuntimeContract

/// Compiler-emitted adapters for common concrete results whose imported ABI
/// cannot be reconstructed safely from runtime metadata alone.
enum BuiltInResultAdapters {
    static let all: [RuntimeAutomaticRequirementAdapter] = {
        var adapters: [RuntimeAutomaticRequirementAdapter] = []
        appendFoundationAdapters(to: &adapters)
        return adapters
    }()

    static func append(
        returning resultType: Any.Type,
        resultTransport: RuntimeAutomaticRequirementAdapter.ResultTransport,
        synchronous: RuntimeTypedWitnessAdapterToken,
        synchronousThrowing: RuntimeTypedWitnessAdapterToken,
        asynchronous: RuntimeTypedWitnessAdapterToken,
        asynchronousThrowing: RuntimeTypedWitnessAdapterToken,
        to adapters: inout [RuntimeAutomaticRequirementAdapter]
    ) {
        for kind in [RuntimeRequirementKind.method, .getter] {
            adapters.append(
                adapter(
                    kind: kind,
                    returning: resultType,
                    resultTransport: resultTransport,
                    isThrowing: false,
                    isAsync: false,
                    token: synchronous
                )
            )
            adapters.append(
                adapter(
                    kind: kind,
                    returning: resultType,
                    resultTransport: resultTransport,
                    isThrowing: true,
                    isAsync: false,
                    token: synchronousThrowing
                )
            )
            adapters.append(
                adapter(
                    kind: kind,
                    returning: resultType,
                    resultTransport: resultTransport,
                    isThrowing: false,
                    isAsync: true,
                    token: asynchronous
                )
            )
            adapters.append(
                adapter(
                    kind: kind,
                    returning: resultType,
                    resultTransport: resultTransport,
                    isThrowing: true,
                    isAsync: true,
                    token: asynchronousThrowing
                )
            )
        }
    }

    private static func adapter(
        kind: RuntimeRequirementKind,
        returning resultType: Any.Type,
        resultTransport: RuntimeAutomaticRequirementAdapter.ResultTransport,
        isThrowing: Bool,
        isAsync: Bool,
        token: RuntimeTypedWitnessAdapterToken
    ) -> RuntimeAutomaticRequirementAdapter {
        RuntimeAutomaticRequirementAdapter(
            kind: kind,
            argumentTypes: [],
            resultType: resultType,
            resultTransport: resultTransport,
            isThrowing: isThrowing,
            isAsync: isAsync,
            typedWitnessAdapter: token
        )
    }

    static func token<Adapter>(
        for adapter: Adapter
    ) -> RuntimeTypedWitnessAdapterToken {
        RuntimeStubFactory.makeTypedWitnessAdapter(
            adapter,
            invocationType: BuiltInResultInvocation.self,
            makeInvocation: BuiltInResultInvocation.init
        )
    }
}

final class BuiltInResultInvocation: @unchecked Sendable {
    private let endpoint: any RuntimeInvocationEndpoint
    private let slot: Int

    init(endpoint: any RuntimeInvocationEndpoint, slot: Int) {
        self.endpoint = endpoint
        self.slot = slot
    }

    func call<Result>(returning resultType: Result.Type = Result.self) -> Result {
        do {
            return try endpoint.dispatchTyped(request, as: resultType)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing built-in result adapter for '\(methodName)' threw \(error)."
            )
        }
    }

    func callThrowing<Result>(
        returning resultType: Result.Type = Result.self
    ) throws -> Result {
        try endpoint.dispatchTyped(request, as: resultType)
    }

    func call<Result>(
        returning resultType: Result.Type = Result.self
    ) async -> Result {
        do {
            return try await callAsync(returning: resultType)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing async built-in result adapter for '\(methodName)' threw \(error)."
            )
        }
    }

    func callThrowing<Result>(
        returning resultType: Result.Type = Result.self
    ) async throws -> Result {
        try await callAsync(returning: resultType)
    }

    private var request: RuntimeInvocationRequest {
        RuntimeInvocationRequest(slot: slot, arguments: [])
    }

    private var methodName: String { endpoint.methodName(at: slot) }

    private func callAsync<Result>(returning resultType: Result.Type) async throws -> Result {
        switch endpoint.prepareAsyncDispatch(request) {
            case .recording:
                return requireStubbedResult(
                    endpoint.recordingAccessorResult(at: slot),
                    as: resultType,
                    method: methodName
                )
            case .immediate(.success(let result)):
                return requireStubbedResult(
                    result,
                    as: resultType,
                    method: methodName
                )
            case .immediate(.failure(let error)):
                throw error
            case .suspending(let handler):
                return requireStubbedResult(
                    try await handler([]),
                    as: resultType,
                    method: methodName
                )
            case .forwarding:
                preconditionFailure(
                    "[TestDoubles] Built-in result adapters cannot dispatch a forwarding Spy fallback."
                )
        }
    }
}
