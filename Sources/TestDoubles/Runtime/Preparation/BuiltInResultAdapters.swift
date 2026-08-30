import InternalRuntimeContract

/// Compiler-emitted adapters for common concrete results whose imported ABI
/// cannot be reconstructed safely from runtime metadata alone.
enum BuiltInResultAdapters {
    static let all: [RuntimeAutomaticRequirementAdapter] = {
        var adapters: [RuntimeAutomaticRequirementAdapter] = []
        appendFoundationAdapters(to: &adapters)
        return adapters
    }()

    /// Result-transport evidence safe to use while preparing a forwarding
    /// Spy. Executable adapters remain exclusive to non-forwarding Stubs.
    static let transportEvidenceOnly = all.filter {
        $0.typedWitnessAdapter == nil
    }

    static func append<Result>(
        returning resultType: Result.Type,
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
        for kind in [RuntimeRequirementKind.method, .getter] {
            for (isThrowing, isAsync) in [
                (false, false),
                (true, false),
                (false, true),
                (true, true)
            ] {
                adapters.append(
                    RuntimeAutomaticRequirementAdapter(
                        kind: kind,
                        resultType: resultType,
                        resultTransport: resultTransport,
                        isThrowing: isThrowing,
                        isAsync: isAsync
                    )
                )
            }
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

    func call(returning resultType: Any.Type) -> Any {
        do {
            return try dispatchErased(returning: resultType)
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing built-in result adapter for '\(methodName)' threw \(error)."
            )
        }
    }

    func callThrowing(returning resultType: Any.Type) throws -> Any {
        try dispatchErased(returning: resultType)
    }

    func call() async -> Any {
        do {
            return try await callAsync()
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing async built-in result adapter for '\(methodName)' threw \(error)."
            )
        }
    }

    func callThrowing() async throws -> Any {
        try await callAsync()
    }

    private var request: RuntimeInvocationRequest {
        RuntimeInvocationRequest(slot: slot, arguments: [])
    }

    private var methodName: String { endpoint.methodName(at: slot) }

    private func dispatchErased(returning resultType: Any.Type) throws -> Any {
        func dispatch<Result>(as resultType: Result.Type) throws -> Any {
            try endpoint.dispatchTyped(request, as: resultType)
        }
        return try _openExistential(resultType, do: dispatch)
    }

    private func callAsync() async throws -> Any {
        switch endpoint.prepareAsyncDispatch(request) {
            case .recording:
                return endpoint.recordingAccessorResult(at: slot)
            case .immediate(.success(let result)):
                return result
            case .immediate(.failure(let error)):
                throw error
            case .suspending(let handler):
                return try await handler([])
            case .forwarding:
                preconditionFailure(
                    "[TestDoubles] Built-in result adapters cannot dispatch a forwarding Spy fallback."
                )
        }
    }
}
