import BenchmarkFixtures
import TestDoubles

@inline(never)
func invokeUnary(_ service: any UnaryBenchmarkService, value: Int) -> Int {
    service.transform(value)
}

@inline(never)
func invokeUnaryBatch(
    _ service: any UnaryBenchmarkService,
    seed: Int
) -> Int {
    var value = seed
    for offset in 0 ..< 64 {
        value = service.transform(value &+ offset)
    }
    return value
}

@inline(never)
func invokeZero(_ service: any ArityBenchmarkService) -> Int {
    service.zero()
}

@inline(never)
func invokeOne(_ service: any ArityBenchmarkService, value: Int) -> Int {
    service.one(value)
}

@inline(never)
func invokeSix(_ service: any ArityBenchmarkService, value: Int) -> Int {
    service.six(value, value, value, value, value, value)
}

@inline(never)
func invokeVoid(_ service: any VoidBenchmarkService, value: Int) {
    service.consume(value)
}

@inline(never)
func invokeVector(
    _ service: any VectorBenchmarkService,
    value: SIMD4<Float>
) -> SIMD4<Float> {
    service.transform(value)
}

@inline(never)
func invokeReference(
    _ service: any ReferenceBenchmarkService,
    value: BenchmarkBox
) -> BenchmarkBox {
    service.echo(value)
}

@inline(never)
func invokeAsync(
    _ service: any AsyncBenchmarkService,
    value: Int
) async -> Int {
    await service.transform(value)
}

@inline(never)
func invokeAsyncStack(
    _ service: any AsyncStackBenchmarkService,
    value: Int
) async -> Int {
    #if arch(x86_64)
        await service.transform(value, value, value, value, value, value, value)
    #else
        await service.transform(
            value, value, value, value, value, value, value, value, value
        )
    #endif
}

func configureAsyncStack(
    _ stub: Stub<any AsyncStackBenchmarkService>
) async {
    #if arch(x86_64)
        await stub.when {
            await $0.transform(any(), any(), any(), any(), any(), any(), any())
        }.thenReturn(1)
    #else
        await stub.when {
            await $0.transform(
                any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        }.thenReturn(1)
    #endif
}

func captureSelfArgument<P: SelfBenchmarkService>(_ value: P) {
    value.accept(any(using: value))
}

@inline(never)
func invokeSelfArgument<P: SelfBenchmarkService>(_ value: P) -> Int {
    value.accept(value)
    return value.marker()
}

@inline(never)
func invokeClosure(
    _ service: any ClosureBenchmarkService,
    closure: @escaping BenchmarkClosure
) -> BenchmarkClosure {
    service.echo(closure)
}

@inline(never)
func invokeDictionary(
    _ service: any DictionaryBenchmarkService<Int>
) -> [String: Int] {
    service.values()
}

@inline(never)
func invokeAssociatedError(
    _ service: any AssociatedErrorBenchmarkService<AssociatedBenchmarkFailure>,
    value: Int
) throws(AssociatedBenchmarkFailure) -> Int {
    try service.load(value)
}

@inline(never)
func invokeRead(_ service: any ReadBenchmarkService) -> Int {
    service.value
}

@inline(never)
func invokeModify(_ service: inout any ModifyBenchmarkService) -> Int {
    service.value &+= 1
    return service.value
}

func timedSync(
    iterations: Int,
    operation: (Int) throws -> Int
) rethrows -> TimedMeasurement {
    let clock = ContinuousClock()
    var checksum: UInt64 = 0
    let start = clock.now
    for iteration in 0 ..< iterations {
        checksum &+= UInt64(truncatingIfNeeded: try operation(iteration))
    }
    let end = clock.now
    return TimedMeasurement(
        elapsedNanoseconds: elapsedNanoseconds(from: start, to: end),
        checksum: checksum
    )
}

func timedAsync(
    iterations: Int,
    operation: (Int) async throws -> Int
) async rethrows -> TimedMeasurement {
    let clock = ContinuousClock()
    var checksum: UInt64 = 0
    let start = clock.now
    for iteration in 0 ..< iterations {
        checksum &+= UInt64(truncatingIfNeeded: try await operation(iteration))
    }
    let end = clock.now
    return TimedMeasurement(
        elapsedNanoseconds: elapsedNanoseconds(from: start, to: end),
        checksum: checksum
    )
}

func benchmarkDefinitions() -> [BenchmarkDefinition] {
    [
        BenchmarkDefinition(
            name: benchmarkControlName,
            preExpansionComparable: true,
            pilotIterations: 10_000,
            maximumIterations: 5_000_000
        ) { iterations in
            let service: any UnaryBenchmarkService = LinkedUnaryBenchmarkService()
            return timedSync(iterations: iterations) {
                invokeUnaryBatch(service, seed: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.construct.steady-automatic",
            preExpansionComparable: true,
            pilotIterations: 5,
            maximumIterations: 1_000
        ) { iterations in
            _ = LinkedUnaryBenchmarkService()
            return try timedSync(iterations: iterations) { iteration in
                _ = try Stub<any UnaryBenchmarkService>()
                return iteration
            }
        },
        BenchmarkDefinition(
            name: "stub.construct.steady-explicit",
            preExpansionComparable: true,
            pilotIterations: 5,
            maximumIterations: 1_000
        ) { iterations in
            let requirement: Stub<any UnaryBenchmarkService>.Requirement =
                .method(Int.self, returning: Int.self)
            return try timedSync(iterations: iterations) { iteration in
                _ = try Stub<any UnaryBenchmarkService>(requirement)
                return iteration
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.arity0",
            preExpansionComparable: true,
            pilotIterations: 500,
            maximumIterations: 100_000
        ) { iterations in
            _ = LinkedArityBenchmarkService()
            let stub = try Stub<any ArityBenchmarkService>()
            stub.when { $0.zero() }.thenReturn(1)
            let service: any ArityBenchmarkService = stub()
            return timedSync(iterations: iterations) { _ in invokeZero(service) }
        },
        BenchmarkDefinition(
            name: "stub.invoke.arity1",
            preExpansionComparable: true,
            pilotIterations: 500,
            maximumIterations: 100_000
        ) { iterations in
            _ = LinkedArityBenchmarkService()
            let stub = try Stub<any ArityBenchmarkService>()
            stub.when { $0.one(any()) }.then { (value: Int) in value &+ 1 }
            let service: any ArityBenchmarkService = stub()
            return timedSync(iterations: iterations) {
                invokeOne(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.arity6",
            preExpansionComparable: true,
            pilotIterations: 200,
            maximumIterations: 50_000
        ) { iterations in
            _ = LinkedArityBenchmarkService()
            let stub = try Stub<any ArityBenchmarkService>()
            stub.when {
                $0.six(any(), any(), any(), any(), any(), any())
            }.then {
                (
                    first: Int,
                    second: Int,
                    third: Int,
                    fourth: Int,
                    fifth: Int,
                    sixth: Int
                ) in
                first &+ second &+ third &+ fourth &+ fifth &+ sixth
            }
            let service: any ArityBenchmarkService = stub()
            return timedSync(iterations: iterations) {
                invokeSix(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.void",
            preExpansionComparable: true,
            pilotIterations: 500,
            maximumIterations: 100_000
        ) { iterations in
            _ = LinkedVoidBenchmarkService()
            let stub = try Stub<any VoidBenchmarkService>()
            stub.when { $0.consume(any()) }.thenDoNothing()
            let service: any VoidBenchmarkService = stub()
            return timedSync(iterations: iterations) { iteration in
                invokeVoid(service, value: iteration)
                return iteration
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.reference",
            preExpansionComparable: true,
            pilotIterations: 200,
            maximumIterations: 50_000
        ) { iterations in
            _ = LinkedReferenceBenchmarkService()
            let placeholder = BenchmarkBox(value: -1)
            let stub = try Stub<any ReferenceBenchmarkService>()
            stub.when(returning: placeholder) {
                $0.echo(any(using: placeholder))
            }.then { (value: BenchmarkBox) in value }
            let service: any ReferenceBenchmarkService = stub()
            let value = BenchmarkBox(value: 42)
            return timedSync(iterations: iterations) { _ in
                invokeReference(service, value: value).value
            }
        },
        BenchmarkDefinition(
            name: "stub.match.last-of-eight",
            preExpansionComparable: true,
            pilotIterations: 200,
            maximumIterations: 50_000
        ) { iterations in
            _ = LinkedUnaryBenchmarkService()
            let stub = try Stub<any UnaryBenchmarkService>()
            for value in 0 ..< 8 {
                stub.when { $0.transform(value) }.thenReturn(value)
            }
            let service: any UnaryBenchmarkService = stub()
            return timedSync(iterations: iterations) { _ in
                invokeUnary(service, value: 7)
            }
        },
        BenchmarkDefinition(
            name: "stub.match.capture",
            preExpansionComparable: true,
            pilotIterations: 200,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedUnaryBenchmarkService()
            let captor = ArgumentCaptor<Int>()
            let stub = try Stub<any UnaryBenchmarkService>()
            stub.when { $0.transform(captor.capture()) }.thenReturn(1)
            let service: any UnaryBenchmarkService = stub()
            return timedSync(iterations: iterations) {
                invokeUnary(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.verify.batch",
            preExpansionComparable: true,
            pilotIterations: 200,
            maximumIterations: 50_000
        ) { iterations in
            _ = LinkedUnaryBenchmarkService()
            let stub = try Stub<any UnaryBenchmarkService>()
            stub.when { $0.transform(any()) }.thenReturn(1)
            let service: any UnaryBenchmarkService = stub()
            for iteration in 0 ..< iterations {
                _ = invokeUnary(service, value: iteration)
            }
            let clock = ContinuousClock()
            let start = clock.now
            stub.verify(.exactly(iterations)) { $0.transform(any()) }
            let end = clock.now
            return TimedMeasurement(
                elapsedNanoseconds: elapsedNanoseconds(from: start, to: end),
                checksum: UInt64(iterations)
            )
        },
        BenchmarkDefinition(
            name: "spy.forward.invoke",
            preExpansionComparable: true,
            pilotIterations: 200,
            maximumIterations: 50_000
        ) { iterations in
            let spy = try Spy<any UnaryBenchmarkService>(
                forwardingTo: LinkedUnaryBenchmarkService()
            )
            let service: any UnaryBenchmarkService = spy()
            return timedSync(iterations: iterations) {
                invokeUnary(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.async.immediate",
            preExpansionComparable: true,
            pilotIterations: 100,
            maximumIterations: 20_000
        ) { iterations in
            _ = LinkedAsyncBenchmarkService()
            let stub = try Stub<any AsyncBenchmarkService>()
            await stub.when { await $0.transform(any()) }.then {
                (value: Int) async in value &+ 1
            }
            let service: any AsyncBenchmarkService = stub()
            return await timedAsync(iterations: iterations) {
                await invokeAsync(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.async.stack-word",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 20_000
        ) { iterations in
            _ = LinkedAsyncStackBenchmarkService()
            let stub = try Stub<any AsyncStackBenchmarkService>()
            await configureAsyncStack(stub)
            let service: any AsyncStackBenchmarkService = stub()
            return await timedAsync(iterations: iterations) {
                await invokeAsyncStack(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.self-argument",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedSelfBenchmarkService()
            let stub = try Stub<any SelfBenchmarkService>()
            stub.when { captureSelfArgument($0) }.thenDoNothing()
            stub.when { $0.marker() }.thenReturn(1)
            let service: any SelfBenchmarkService = stub()
            return timedSync(iterations: iterations) { _ in
                invokeSelfArgument(service)
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.closure",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedClosureBenchmarkService()
            let identity: BenchmarkClosure = { $0 &+ 1 }
            let stub = try Stub<any ClosureBenchmarkService>()
            stub.when(returning: identity) {
                $0.echo(any(using: identity))
            }.then { (closure: @escaping BenchmarkClosure) in closure }
            let service: any ClosureBenchmarkService = stub()
            return timedSync(iterations: iterations) {
                invokeClosure(service, closure: identity)($0)
            }
        },
        BenchmarkDefinition(
            name: "associated.dictionary.construct.steady",
            preExpansionComparable: false,
            pilotIterations: 5,
            maximumIterations: 1_000
        ) { iterations in
            _ = LinkedDictionaryBenchmarkService()
            return try timedSync(iterations: iterations) { iteration in
                _ = try Stub<any DictionaryBenchmarkService<Int>>()
                return iteration
            }
        },
        BenchmarkDefinition(
            name: "associated.dictionary.invoke",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedDictionaryBenchmarkService()
            let placeholder = ["placeholder": -1]
            let stub = try Stub<any DictionaryBenchmarkService<Int>>()
            stub.when(returning: placeholder) { $0.values() }
                .thenReturn(["value": 42])
            let service: any DictionaryBenchmarkService<Int> = stub()
            return timedSync(iterations: iterations) { _ in
                invokeDictionary(service)["value"] ?? 0
            }
        },
        BenchmarkDefinition(
            name: "associated.typed-error.construct.steady",
            preExpansionComparable: false,
            pilotIterations: 5,
            maximumIterations: 1_000
        ) { iterations in
            _ = LinkedAssociatedErrorBenchmarkService()
            typealias Service = any AssociatedErrorBenchmarkService<
                AssociatedBenchmarkFailure
            >
            return try timedSync(iterations: iterations) { iteration in
                _ = try Stub<Service>()
                return iteration
            }
        },
        BenchmarkDefinition(
            name: "associated.typed-error.return",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedAssociatedErrorBenchmarkService()
            typealias Service = any AssociatedErrorBenchmarkService<
                AssociatedBenchmarkFailure
            >
            let stub = try Stub<Service>()
            stub.when { try $0.load(any()) }.then {
                (value: Int) throws(AssociatedBenchmarkFailure) -> Int in
                value &+ 1
            }
            let service: Service = stub()
            return try timedSync(iterations: iterations) {
                try invokeAssociatedError(service, value: $0)
            }
        },
        BenchmarkDefinition(
            name: "associated.typed-error.throw",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedAssociatedErrorBenchmarkService()
            typealias Service = any AssociatedErrorBenchmarkService<
                AssociatedBenchmarkFailure
            >
            let stub = try Stub<Service>()
            stub.when { try $0.load(any()) }
                .thenThrow(AssociatedBenchmarkFailure(code: 42))
            let service: Service = stub()
            return timedSync(iterations: iterations) { iteration in
                do {
                    return try invokeAssociatedError(service, value: iteration)
                } catch let error as AssociatedBenchmarkFailure {
                    return error.code
                } catch {
                    preconditionFailure("Unexpected benchmark error: \(error)")
                }
            }
        },
        BenchmarkDefinition(
            name: "accessor.read.invoke",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedReadBenchmarkService()
            let stub = try Stub<any ReadBenchmarkService>()
            stub.when { $0.value }.thenReturn(42)
            let service: any ReadBenchmarkService = stub()
            return timedSync(iterations: iterations) { _ in invokeRead(service) }
        },
        BenchmarkDefinition(
            name: "accessor.modify.forward",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            let spy = try Spy<any ModifyBenchmarkService>(
                forwardingTo: LinkedModifyBenchmarkService()
            )
            var service: any ModifyBenchmarkService = spy()
            return timedSync(iterations: iterations) { _ in
                invokeModify(&service)
            }
        },
        BenchmarkDefinition(
            name: "stub.invoke.vector128",
            preExpansionComparable: false,
            pilotIterations: 100,
            maximumIterations: 25_000
        ) { iterations in
            _ = LinkedVectorBenchmarkService()
            let stub = try Stub<any VectorBenchmarkService>(
                .method(signatureOf: VectorBenchmarkService.transform)
            )
            let placeholder = SIMD4<Float>(repeating: 0)
            stub.when(returning: placeholder) {
                $0.transform(any(using: placeholder))
            }.then {
                (value: SIMD4<Float>) in value
            }
            let service: any VectorBenchmarkService = stub()
            return timedSync(iterations: iterations) { iteration in
                let value = invokeVector(
                    service,
                    value: SIMD4<Float>(repeating: Float(iteration))
                )
                return Int(value.x)
            }
        }
    ]
}
