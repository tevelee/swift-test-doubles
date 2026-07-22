public protocol UnaryBenchmarkService {
    func transform(_ value: Int) -> Int
}

public struct LinkedUnaryBenchmarkService: UnaryBenchmarkService {
    public init() {}

    @inline(never)
    public func transform(_ value: Int) -> Int { value &+ 1 }
}

public protocol ArityBenchmarkService {
    func zero() -> Int
    func one(_ value: Int) -> Int
    func six(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int
    ) -> Int
}

public struct LinkedArityBenchmarkService: ArityBenchmarkService {
    public init() {}

    public func zero() -> Int { 1 }
    public func one(_ value: Int) -> Int { value }
    public func six(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int
    ) -> Int {
        first &+ second &+ third &+ fourth &+ fifth &+ sixth
    }
}

public protocol VoidBenchmarkService {
    func consume(_ value: Int)
}

public struct LinkedVoidBenchmarkService: VoidBenchmarkService {
    public init() {}

    @inline(never)
    public func consume(_ value: Int) {}
}

public protocol VectorBenchmarkService {
    func transform(_ value: SIMD4<Float>) -> SIMD4<Float>
}

public struct LinkedVectorBenchmarkService: VectorBenchmarkService {
    public init() {}

    @inline(never)
    public func transform(_ value: SIMD4<Float>) -> SIMD4<Float> { value }
}

public final class BenchmarkBox {
    public let value: Int

    public init(value: Int) {
        self.value = value
    }
}

public protocol ReferenceBenchmarkService {
    func echo(_ value: BenchmarkBox) -> BenchmarkBox
}

public struct LinkedReferenceBenchmarkService: ReferenceBenchmarkService {
    public init() {}

    public func echo(_ value: BenchmarkBox) -> BenchmarkBox { value }
}

public protocol AsyncBenchmarkService {
    func transform(_ value: Int) async -> Int
}

public struct LinkedAsyncBenchmarkService: AsyncBenchmarkService {
    public init() {}

    public func transform(_ value: Int) async -> Int { value &+ 1 }
}

public protocol AsyncStackBenchmarkService: Sendable {
    #if arch(x86_64)
        func transform(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int
    #else
        func transform(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int
    #endif
}

public struct LinkedAsyncStackBenchmarkService: AsyncStackBenchmarkService {
    public init() {}

    #if arch(x86_64)
        public func transform(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int
        ) async -> Int { a6 }
    #else
        public func transform(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int,
            _ a5: Int, _ a6: Int, _ a7: Int, _ a8: Int
        ) async -> Int { a8 }
    #endif
}

public protocol SelfBenchmarkService {
    func accept(_ value: Self)
    func marker() -> Int
}

public struct LinkedSelfBenchmarkService: SelfBenchmarkService {
    public init() {}

    public func accept(_ value: Self) {}
    public func marker() -> Int { 0 }
}

public typealias BenchmarkClosure = @Sendable (Int) -> Int

public protocol ClosureBenchmarkService {
    func echo(_ closure: @escaping BenchmarkClosure) -> BenchmarkClosure
}

public struct LinkedClosureBenchmarkService: ClosureBenchmarkService {
    public init() {}

    public func echo(
        _ closure: @escaping BenchmarkClosure
    ) -> BenchmarkClosure {
        closure
    }
}

public protocol DictionaryBenchmarkService<Value> {
    associatedtype Value
    func values() -> [String: Value]
}

public struct LinkedDictionaryBenchmarkService: DictionaryBenchmarkService {
    public init() {}

    public func values() -> [String: Int] { ["linked": 0] }
}

public struct AssociatedBenchmarkFailure: Error {
    public let code: Int

    public init(code: Int) {
        self.code = code
    }
}

public protocol AssociatedErrorBenchmarkService<Failure> {
    associatedtype Failure: Error
    func load(_ value: Int) throws(Failure) -> Int
}

public struct LinkedAssociatedErrorBenchmarkService:
    AssociatedErrorBenchmarkService
{
    public init() {}

    public func load(
        _ value: Int
    ) throws(AssociatedBenchmarkFailure) -> Int {
        value
    }
}

public protocol ReadBenchmarkService {
    var value: Int { read }
}

public struct LinkedReadBenchmarkService: ReadBenchmarkService {
    public init() {}

    public var value: Int {
        read { yield 0 }
    }
}

public protocol ModifyBenchmarkService {
    var value: Int { get set }
}

public struct LinkedModifyBenchmarkService: ModifyBenchmarkService {
    private var storage = 0

    public init() {}

    public var value: Int {
        get { storage }
        set { storage = newValue }
        _modify { yield &storage }
    }
}
