import Testing
import TestDoubles

private protocol DummyService {
    func value() -> Int
    func load() async -> String
    var count: Int { get set }
}

private protocol DummyCallbackService {
    func transform(
        _ value: SIMD4<Float>,
        using transform: (SIMD4<Float>) -> SIMD4<Float>
    ) -> SIMD4<Float>
}

private protocol DummySource<Element> {
    associatedtype Element
    func load() -> Element
}

private protocol DummyBaseService {
    func baseValue() -> Int
}

private protocol DummyDerivedService: DummyBaseService {
    func derivedValue() -> Int
}

private protocol DummyCompanionService {
    func companionValue() -> Int
}

private protocol DummyObjectService: AnyObject {
    func value() -> Int
}

private protocol DummyStaticService {
    static func value() -> Int
}

@inline(never)
private func fallbackValue(using service: any DummyService) -> Int {
    withExtendedLifetime(service) { 42 }
}

@inline(never)
private func acceptsCallbackService(
    _ service: any DummyCallbackService
) -> Bool {
    withExtendedLifetime(service) { true }
}

@inline(never)
private func acceptsObjectService(
    _ service: any DummyObjectService
) -> Bool {
    withExtendedLifetime(service) { true }
}

@inline(never)
private func invokeStaticRequirement<T: DummyStaticService>(
    on service: T
) -> Int {
    type(of: service).value()
}

@Suite("Dummy test doubles")
struct DummyTests {
    @Test func factorySuppliesAnUnusedProtocolDependencyWithoutAConformer() {
        let service: any DummyService = makeDummy()

        #expect(fallbackValue(using: service) == 42)
    }

    @Test func constructionDoesNotDecodeRequirementSignatures() {
        let dummy = Dummy<any DummyCallbackService>()

        #expect(acceptsCallbackService(dummy()))
    }

    @Test func supportsBoundAssociatedTypes() {
        let source: any DummySource<Int> = makeDummy()
        withExtendedLifetime(source) {}
    }

    @Test func supportsInheritanceAndProtocolCompositions() {
        let dummy = Dummy<
            any DummyDerivedService & DummyCompanionService
        >()

        let service: any DummyDerivedService & DummyCompanionService = dummy()
        withExtendedLifetime(service) {}
    }

    @Test func supportsClassConstrainedProtocols() {
        let dummy = Dummy<any DummyObjectService>()

        let service: any DummyObjectService = dummy()
        #expect(acceptsObjectService(service))
    }

    @Test func generatedValueOwnsItsRuntimeResources() throws {
        var dummy: Dummy<any DummyService>? = Dummy()
        let service = try #require(dummy?())

        dummy = nil

        #expect(fallbackValue(using: service) == 42)
    }

    @Test func repeatedlyMaterializedValuesOwnTheirRuntimeResources() throws {
        var dummy: Dummy<any DummyService>? = Dummy()
        let first = try #require(dummy?())
        let second = try #require(dummy?())

        dummy = nil

        #expect(fallbackValue(using: first) == 42)
        #expect(fallbackValue(using: second) == 42)
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    enum DummyExitScenario: CaseIterable, Sendable {
        case synchronous
        case asynchronous
        case modify
        case staticRequirement
        case nonProtocolConstruction
    }

    @Suite struct DummyInvocationExitTests {
        @Test(.serialized, arguments: DummyExitScenario.allCases)
        func invocationsFailClosedWithRequirementDiagnostics(
            _ scenario: DummyExitScenario
        ) async throws {
            switch scenario {
                case .synchronous:
                    try await synchronousInvocationFailsClosed()
                case .asynchronous:
                    try await asynchronousInvocationFailsClosed()
                case .modify:
                    try await modifyInvocationFailsClosed()
                case .staticRequirement:
                    try await staticInvocationFailsClosed()
                case .nonProtocolConstruction:
                    try await nonProtocolConstructionFailsClosed()
            }
        }

        private func synchronousInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let service: any DummyService = makeDummy()
                _ = service.value()
            }
            try expectDummyDiagnostic(result, containing: "method requirement")
        }

        private func asynchronousInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let service: any DummyService = makeDummy()
                _ = await service.load()
            }
            try expectDummyDiagnostic(result, containing: "method requirement")
        }

        private func modifyInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                var service: any DummyService = makeDummy()
                service.count += 1
            }
            try expectDummyDiagnostic(result, containing: "getter requirement")
        }

        private func staticInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let service: any DummyStaticService = makeDummy()
                _ = invokeStaticRequirement(on: service)
            }
            try expectDummyDiagnostic(
                result,
                protocolName: "DummyStaticService",
                containing: "method requirement"
            )
        }

        private func nonProtocolConstructionFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = Dummy<Int>()
            }
            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("Could not construct a dummy for 'Swift.Int'"))
            #expect(diagnostic.contains("Use a protocol existential"))
        }

        private func expectDummyDiagnostic(
            _ result: ExitTest.Result,
            protocolName: String = "DummyService",
            containing requirementDescription: String
        ) throws {
            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("Dummy<"))
            #expect(diagnostic.contains(protocolName))
            #expect(diagnostic.contains(requirementDescription))
            #expect(
                diagnostic.contains("A dummy may only be passed to code paths that do not use it")
            )
        }
    }
#endif
