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

private struct ConcreteDummyValue {
    let count: Int
    let title: String
    let flags: [Bool]
    let location: (x: Double, y: Double)
    let note: String?
}

private enum EmptyCaseDummyValue {
    case payload(String)
    case empty
}

private enum PayloadOnlyDummyValue {
    case text(String)
    case number(Int)
}

private final class FactoryDummyValue: @unchecked Sendable {
    let identifier: Int

    init(identifier: Int) {
        self.identifier = identifier
    }
}

private final class RegisteredDummyValue: @unchecked Sendable {
    let identifier: Int

    init(identifier: Int) {
        self.identifier = identifier
    }
}

private typealias ConcreteDummyFunction = (Int, String) -> Bool
private typealias ConcreteAsyncDummyFunction = @Sendable (Int) async throws -> String
private typealias ConcreteThinDummyFunction = @convention(thin) (Int) -> Int
private typealias ConcreteCDummyFunction = @convention(c) (Int32) -> Int32
#if canImport(ObjectiveC)
    private typealias ConcreteBlockDummyFunction = @convention(block) (Int) -> Int
#endif

private struct ConcreteDummyFunctionContainer {
    let count: Int
    let transform: ConcreteDummyFunction
    let asynchronous: ConcreteAsyncDummyFunction
}

private struct ConcreteOpaqueExistentialContainer {
    let value: Any
    let object: AnyObject
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
        let service: any DummyService = Dummy.make()

        #expect(fallbackValue(using: service) == 42)
    }

    @Test func constructionDoesNotDecodeRequirementSignatures() throws {
        let dummy = try Dummy<any DummyCallbackService>()

        #expect(acceptsCallbackService(dummy()))
    }

    @Test func supportsBoundAssociatedTypes() {
        let source: any DummySource<Int> = Dummy.make()
        withExtendedLifetime(source) {}
    }

    @Test func supportsInheritanceAndProtocolCompositions() throws {
        let dummy = try Dummy<
            any DummyDerivedService & DummyCompanionService
        >()

        let service: any DummyDerivedService & DummyCompanionService = dummy()
        withExtendedLifetime(service) {}
    }

    @Test func supportsClassConstrainedProtocols() throws {
        let dummy = try Dummy<any DummyObjectService>()

        let service: any DummyObjectService = dummy()
        #expect(acceptsObjectService(service))
    }

    @Test func generatedValueOwnsItsRuntimeResources() throws {
        var dummy: Dummy<any DummyService>? = try Dummy()
        let service = try #require(dummy?())

        dummy = nil

        #expect(fallbackValue(using: service) == 42)
    }

    @Test func repeatedlyMaterializedValuesOwnTheirRuntimeResources() throws {
        var dummy: Dummy<any DummyService>? = try Dummy()
        let first = try #require(dummy?())
        let second = try #require(dummy?())

        dummy = nil

        #expect(fallbackValue(using: first) == 42)
        #expect(fallbackValue(using: second) == 42)
    }

    @Test func synthesizesScalarDummyValues() throws {
        let dummy = try Dummy<Int>()
        #expect(dummy() == 0)
        #expect(Dummy<String>.make() == "")
    }

    @Test func synthesizesAggregateDummyValues() throws {
        let value: ConcreteDummyValue = try Dummy()()

        #expect(value.count == 0)
        #expect(value.title == "")
        #expect(value.flags.isEmpty)
        #expect(value.location.x == 0)
        #expect(value.location.y == 0)
        #expect(value.note == nil)
    }

    @Test func synthesizesAnEmptyEnumCase() {
        let value: EmptyCaseDummyValue = Dummy.make()
        guard case .empty = value else {
            Issue.record("Expected the synthesized empty enum case")
            return
        }
    }

    @Test func synthesizesAPayloadOnlyEnumCase() {
        let value: PayloadOnlyDummyValue = Dummy.make()
        guard case .text("") = value else {
            Issue.record("Expected the first safely synthesizable payload case")
            return
        }
    }

    @Test func acceptsAFactoryForUnsupportedConcreteTypes() throws {
        expectStubError({
            _ = try Dummy<FactoryDummyValue>()
        }) { error in
            guard case .dummyValueNotSynthesizable = error else { return false }
            return true
        }

        let generated = Dummy<FactoryDummyValue>(using: {
            FactoryDummyValue(identifier: 41)
        })
        let made: FactoryDummyValue = Dummy.make(using: {
            FactoryDummyValue(identifier: 42)
        })

        #expect(generated().identifier == 41)
        #expect(made.identifier == 42)
    }

    @Test func registeredFactorySupportsOrdinaryClassDummyConstruction() throws {
        Dummy<RegisteredDummyValue>.register {
            RegisteredDummyValue(identifier: 43)
        }
        defer { Dummy<RegisteredDummyValue>.unregister() }

        let generated = try Dummy<RegisteredDummyValue>()()
        let made: RegisteredDummyValue = Dummy.make()

        #expect(generated.identifier == 43)
        #expect(made.identifier == 43)
    }

    @Test func synthesizesUnusedFunctionValues() {
        let synchronous: ConcreteDummyFunction = Dummy.make()
        let asynchronous: ConcreteAsyncDummyFunction = Dummy.make()
        let thin: ConcreteThinDummyFunction = Dummy.make()
        let c: ConcreteCDummyFunction = Dummy.make()

        withExtendedLifetime(synchronous) {}
        withExtendedLifetime(asynchronous) {}
        withExtendedLifetime(thin) {}
        withExtendedLifetime(c) {}
        #if canImport(ObjectiveC)
            let block: ConcreteBlockDummyFunction = Dummy.make()
            withExtendedLifetime(block) {}
        #endif
    }

    @Test func recursivelySynthesizesFunctionFields() {
        let container: ConcreteDummyFunctionContainer = Dummy.make()

        #expect(container.count == 0)
        withExtendedLifetime(container.transform) {}
        withExtendedLifetime(container.asynchronous) {}
    }

    @Test func synthesizesOpaqueExistentials() {
        let value: Any = Dummy.make()
        let object: AnyObject = Dummy.make()
        let container: ConcreteOpaqueExistentialContainer = Dummy.make()

        withExtendedLifetime(value) {}
        withExtendedLifetime(object) {}
        withExtendedLifetime(container) {}
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    enum DummyExitScenario: CaseIterable, Sendable {
        case synchronous
        case asynchronous
        case modify
        case staticRequirement
        case function
        case asyncFunction
        case nestedFunction
        case thinFunction
        case cFunction
        #if canImport(ObjectiveC)
            case blockFunction
        #endif
        case unsupportedConcreteFactoryConstruction
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
                case .function:
                    try await functionInvocationFailsClosed()
                case .asyncFunction:
                    try await asyncFunctionInvocationFailsClosed()
                case .nestedFunction:
                    try await nestedFunctionInvocationFailsClosed()
                case .thinFunction:
                    try await thinFunctionInvocationFailsClosed()
                case .cFunction:
                    try await cFunctionInvocationFailsClosed()
                #if canImport(ObjectiveC)
                    case .blockFunction:
                        try await blockFunctionInvocationFailsClosed()
                #endif
                case .unsupportedConcreteFactoryConstruction:
                    try await unsupportedConcreteFactoryConstructionFailsClosed()
            }
        }

        private func synchronousInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let service: any DummyService = Dummy.make()
                _ = service.value()
            }
            try expectDummyDiagnostic(result, containing: "method requirement")
        }

        private func asynchronousInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let service: any DummyService = Dummy.make()
                _ = await service.load()
            }
            try expectDummyDiagnostic(result, containing: "method requirement")
        }

        private func modifyInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                var service: any DummyService = Dummy.make()
                service.count += 1
            }
            try expectDummyDiagnostic(result, containing: "getter requirement")
        }

        private func staticInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let service: any DummyStaticService = Dummy.make()
                _ = invokeStaticRequirement(on: service)
            }
            try expectDummyDiagnostic(
                result,
                protocolName: "DummyStaticService",
                containing: "method requirement"
            )
        }

        private func functionInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let function: ConcreteDummyFunction = Dummy.make()
                _ = function(1, "unused")
            }
            try expectDummyFunctionDiagnostic(result)
        }

        private func asyncFunctionInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let function: ConcreteAsyncDummyFunction = Dummy.make()
                _ = try await function(1)
            }
            try expectDummyFunctionDiagnostic(result)
        }

        private func nestedFunctionInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let container: ConcreteDummyFunctionContainer = Dummy.make()
                _ = container.transform(1, "unused")
            }
            try expectDummyFunctionDiagnostic(result)
        }

        private func thinFunctionInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let function: ConcreteThinDummyFunction = Dummy.make()
                _ = function(1)
            }
            try expectDummyFunctionDiagnostic(result)
        }

        private func cFunctionInvocationFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let function: ConcreteCDummyFunction = Dummy.make()
                _ = function(1)
            }
            try expectDummyFunctionDiagnostic(result)
        }

        #if canImport(ObjectiveC)
            private func blockFunctionInvocationFailsClosed() async throws {
                let result = try await #require(
                    processExitsWith: .failure,
                    observing: [\.standardErrorContent]
                ) {
                    let function: ConcreteBlockDummyFunction = Dummy.make()
                    _ = function(1)
                }
                try expectDummyFunctionDiagnostic(result)
            }
        #endif

        private func expectDummyFunctionDiagnostic(
            _ result: ExitTest.Result
        ) throws {
            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("A dummy function was invoked"))
            #expect(
                diagnostic.contains("may only be passed to code paths that do not use it")
            )
        }

        private func unsupportedConcreteFactoryConstructionFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                _ = Dummy.make(FactoryDummyValue.self)
            }
            let diagnostic = try #require(
                String(bytes: result.standardErrorContent, encoding: .utf8)
            )
            #expect(diagnostic.contains("Could not construct a dummy for"))
            #expect(diagnostic.contains("FactoryDummyValue"))
            #expect(diagnostic.contains("Dummy.make(using:)"))
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
