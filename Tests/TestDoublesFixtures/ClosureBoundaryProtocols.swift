public typealias ExternalCFunction = @convention(c) (Int32) -> Int32

#if canImport(ObjectiveC)
    public typealias ExternalBlockFunction =
        @convention(block) (Int32) -> Int32
#endif

public func externalCIncrement(_ value: Int32) -> Int32 { value + 1 }
public func externalCDouble(_ value: Int32) -> Int32 { value * 2 }

/// Compiled separately from TestDoubles so convention recovery cannot use
/// protocol source or declaration annotations.
public protocol ExternalFunctionConventionService {
    func cFunction(_ function: ExternalCFunction) -> ExternalCFunction
    #if canImport(ObjectiveC)
        func blockFunction(
            _ function: @escaping ExternalBlockFunction
        ) -> ExternalBlockFunction
    #endif
}

public struct RealExternalFunctionConventionService:
    ExternalFunctionConventionService
{
    public init() {}

    public func cFunction(_ function: ExternalCFunction) -> ExternalCFunction {
        function
    }

    #if canImport(ObjectiveC)
        public func blockFunction(
            _ function: @escaping ExternalBlockFunction
        ) -> ExternalBlockFunction {
            function
        }
    #endif
}

public typealias ExternalContainerClosure = @Sendable (Int) -> String
public typealias ExternalClosureTuple = (
    label: String,
    transform: ExternalContainerClosure
)

public struct ExternalClosureBox: Sendable {
    public let label: String
    public let transform: ExternalContainerClosure

    public init(label: String, transform: @escaping ExternalContainerClosure) {
        self.label = label
        self.transform = transform
    }
}

public protocol ExternalClosureContainerService {
    func optional(
        _ closure: ExternalContainerClosure?
    ) -> ExternalContainerClosure?
    func array(
        _ closures: [ExternalContainerClosure]
    ) -> [ExternalContainerClosure]
    func tuple(_ value: ExternalClosureTuple) -> ExternalClosureTuple
    func nominal(_ value: ExternalClosureBox) -> ExternalClosureBox
}

public struct RealExternalClosureContainerService:
    ExternalClosureContainerService
{
    public init() {}

    public func optional(
        _ closure: ExternalContainerClosure?
    ) -> ExternalContainerClosure? { closure }

    public func array(
        _ closures: [ExternalContainerClosure]
    ) -> [ExternalContainerClosure] { closures }

    public func tuple(_ value: ExternalClosureTuple) -> ExternalClosureTuple {
        value
    }

    public func nominal(_ value: ExternalClosureBox) -> ExternalClosureBox {
        value
    }
}

public typealias ExternalNestedNonescapingClosure =
    @Sendable (
        @Sendable (Int) -> Int
    ) -> @Sendable (Int) -> Int

public protocol ExternalNestedNonescapingClosureService {
    func nested(
        _ closure: @escaping ExternalNestedNonescapingClosure
    ) -> ExternalNestedNonescapingClosure
}

public struct RealExternalNestedNonescapingClosureService:
    ExternalNestedNonescapingClosureService
{
    public init() {}

    public func nested(
        _ closure: @escaping ExternalNestedNonescapingClosure
    ) -> ExternalNestedNonescapingClosure { closure }
}

public actor ExternalClosureWorker {
    private var total = 0

    public init() {}

    public func add(_ value: Int) -> Int {
        total += value
        return total
    }
}

public typealias ExternalIsolatedParameterClosure =
    @Sendable (isolated ExternalClosureWorker, Int) async -> Int

public protocol ExternalIsolatedParameterClosureService {
    func isolatedParameter(
        _ closure: @escaping ExternalIsolatedParameterClosure
    ) -> ExternalIsolatedParameterClosure
}

public struct RealExternalIsolatedParameterClosureService:
    ExternalIsolatedParameterClosureService
{
    public init() {}

    public func isolatedParameter(
        _ closure: @escaping ExternalIsolatedParameterClosure
    ) -> ExternalIsolatedParameterClosure { closure }
}

public struct ExternalLargeClosureError: Error, Equatable, Sendable {
    public let first: UInt64
    public let second: UInt64
    public let third: UInt64
    public let fourth: UInt64

    public init(
        first: UInt64,
        second: UInt64,
        third: UInt64,
        fourth: UInt64
    ) {
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
    }
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalIndirectTypedThrowingClosure =
    @Sendable (Int) throws(ExternalLargeClosureError) -> String

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalAsyncIndirectTypedThrowingClosure =
    @Sendable (Int) async throws(ExternalLargeClosureError) -> ExternalNullaryLargeResult

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public protocol ExternalIndirectTypedThrowingClosureService {
    func typedThrowing(
        _ closure: @escaping ExternalIndirectTypedThrowingClosure
    ) -> ExternalIndirectTypedThrowingClosure
    func asyncTypedThrowing(
        _ closure: @escaping ExternalAsyncIndirectTypedThrowingClosure
    ) -> ExternalAsyncIndirectTypedThrowingClosure
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public struct RealExternalIndirectTypedThrowingClosureService:
    ExternalIndirectTypedThrowingClosureService
{
    public init() {}

    public func typedThrowing(
        _ closure: @escaping ExternalIndirectTypedThrowingClosure
    ) -> ExternalIndirectTypedThrowingClosure { closure }

    public func asyncTypedThrowing(
        _ closure: @escaping ExternalAsyncIndirectTypedThrowingClosure
    ) -> ExternalAsyncIndirectTypedThrowingClosure { closure }
}

public protocol ExternalMutableClosureService {
    var transform: ExternalContainerClosure { get set }
}

public struct RealExternalMutableClosureService:
    ExternalMutableClosureService
{
    public var transform: ExternalContainerClosure

    public init(transform: @escaping ExternalContainerClosure) {
        self.transform = transform
    }
}

public protocol ExternalClosureInitializerService {
    init(transform: @escaping ExternalContainerClosure)
    func apply(_ value: Int) -> String
}

public struct RealExternalClosureInitializerService:
    ExternalClosureInitializerService
{
    private let transform: ExternalContainerClosure

    public init(transform: @escaping ExternalContainerClosure) {
        self.transform = transform
    }

    public func apply(_ value: Int) -> String { transform(value) }
}

public protocol ExternalClosureRequirementPositionsService {
    static func staticTransform(
        _ closure: @escaping ExternalContainerClosure
    ) -> ExternalContainerClosure
    func variadic(
        _ closures: ExternalContainerClosure...
    ) -> [ExternalContainerClosure]
    subscript(
        _ closure: @escaping ExternalContainerClosure
    ) -> ExternalContainerClosure { get }
}

public struct RealExternalClosureRequirementPositionsService:
    ExternalClosureRequirementPositionsService
{
    public init() {}

    public static func staticTransform(
        _ closure: @escaping ExternalContainerClosure
    ) -> ExternalContainerClosure { closure }

    public func variadic(
        _ closures: ExternalContainerClosure...
    ) -> [ExternalContainerClosure] { closures }

    public subscript(
        closure: @escaping ExternalContainerClosure
    ) -> ExternalContainerClosure { closure }
}

public protocol ExternalAssociatedClosureService<Handler> {
    associatedtype Handler
    func transform(_ handler: Handler) -> Handler
}

public struct RealExternalAssociatedClosureService:
    ExternalAssociatedClosureService
{
    public init() {}

    public func transform(
        _ handler: @escaping ExternalContainerClosure
    ) -> ExternalContainerClosure { handler }
}

public protocol ExternalConsumingClosureParameterService {
    func consume(
        _ closure: consuming @escaping ExternalContainerClosure
    ) -> String
}

public struct RealExternalConsumingClosureParameterService:
    ExternalConsumingClosureParameterService
{
    public init() {}

    public func consume(
        _ closure: consuming @escaping ExternalContainerClosure
    ) -> String { closure(1) }
}

public protocol ExternalBorrowingClosureParameterService {
    func borrow(
        _ closure: borrowing @escaping ExternalContainerClosure
    ) -> String
}

public struct RealExternalBorrowingClosureParameterService:
    ExternalBorrowingClosureParameterService
{
    public init() {}

    public func borrow(
        _ closure: borrowing @escaping ExternalContainerClosure
    ) -> String { closure(1) }
}

public protocol ExternalAutoclosureParameterService {
    func evaluate(
        _ value: @autoclosure @escaping @Sendable () -> Int
    ) -> Int
    func evaluateFloating(
        _ value: @autoclosure @escaping @Sendable () -> Double
    ) -> Double
    func evaluateAggregate(
        _ value: @autoclosure @escaping @Sendable () -> ExternalNullaryAggregate
    ) -> ExternalNullaryAggregate
    func evaluateLarge(
        _ value: @autoclosure @escaping @Sendable () -> ExternalNullaryLargeResult
    ) -> ExternalNullaryLargeResult
}

public struct ExternalNullaryAggregate: Equatable, Sendable {
    public let label: String
    public let count: Int
    public let enabled: Bool

    public init(label: String, count: Int, enabled: Bool) {
        self.label = label
        self.count = count
        self.enabled = enabled
    }
}

public struct ExternalNullaryLargeResult: Equatable, Sendable {
    public let first: Int
    public let second: Int
    public let third: Int
    public let fourth: Int
    public let fifth: Int

    public init(first: Int, second: Int, third: Int, fourth: Int, fifth: Int) {
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
        self.fifth = fifth
    }
}

public struct RealExternalAutoclosureParameterService:
    ExternalAutoclosureParameterService
{
    public init() {}

    public func evaluate(
        _ value: @autoclosure @escaping @Sendable () -> Int
    ) -> Int { value() }

    public func evaluateFloating(
        _ value: @autoclosure @escaping @Sendable () -> Double
    ) -> Double { value() }

    public func evaluateAggregate(
        _ value: @autoclosure @escaping @Sendable () -> ExternalNullaryAggregate
    ) -> ExternalNullaryAggregate { value() }

    public func evaluateLarge(
        _ value: @autoclosure @escaping @Sendable () -> ExternalNullaryLargeResult
    ) -> ExternalNullaryLargeResult { value() }
}

public struct ExternalWideClosureArgument: Sendable {
    public let label: String
    public let first: Int
    public let second: Int
    public let third: Int
    public let fourth: Int

    public init(
        label: String,
        first: Int,
        second: Int,
        third: Int,
        fourth: Int
    ) {
        self.label = label
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
    }
}

public enum ExternalDynamicClosureError: Error, Equatable, Sendable {
    case rejected(Int)
}

public struct ExternalMixedClosureError: Error, Equatable, Sendable {
    public let code: Int
    public let ratio: Double

    public init(code: Int, ratio: Double) {
        self.code = code
        self.ratio = ratio
    }
}

public typealias ExternalWideUnaryClosure =
    @Sendable (ExternalWideClosureArgument) -> String
public typealias ExternalMixedBinaryClosure =
    @Sendable (Int, Double) -> ExternalNullaryAggregate
public typealias ExternalMixedTernaryClosure =
    @Sendable (Float, Int, String) -> Double
public typealias ExternalMixedQuaternaryClosure =
    @Sendable (Int, Double, Bool, String) -> String
public typealias ExternalMixedQuinaryClosure =
    @Sendable (Int, Double, Bool, Float, String) -> String
public typealias ExternalSenaryClosure =
    @Sendable (Int, Int, Int, Int, Int, Int) -> Int
public typealias ExternalThrowingQuaternaryClosure =
    @Sendable (Int, Double, Bool, String) throws -> String
public typealias ExternalOptionalHigherOrderClosure =
    @Sendable (
        ExternalContainerClosure?,
        Int
    ) -> ExternalContainerClosure?

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalTypedNullaryClosure =
    () throws(ExternalDynamicClosureError) -> Int
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalTypedQuaternaryClosure =
    @Sendable (Int, Double, Bool, String)
    throws(ExternalDynamicClosureError) -> String
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalMixedTypedBinaryClosure =
    @Sendable (Int, Double)
    throws(ExternalMixedClosureError) -> ExternalNullaryAggregate
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalTypedIndirectSuccessClosure =
    @Sendable (Int)
    throws(ExternalDynamicClosureError) -> ExternalNullaryLargeResult
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalTypedHigherOrderClosure =
    @Sendable (@escaping ExternalContainerClosure, Int)
    throws(ExternalDynamicClosureError) -> ExternalContainerClosure

public protocol ExternalDynamicArityClosureService {
    func wideUnary(
        _ closure: @escaping ExternalWideUnaryClosure
    ) -> ExternalWideUnaryClosure
    func mixedBinary(
        _ closure: @escaping ExternalMixedBinaryClosure
    ) -> ExternalMixedBinaryClosure
    func mixedTernary(
        _ closure: @escaping ExternalMixedTernaryClosure
    ) -> ExternalMixedTernaryClosure
    func mixedQuaternary(
        _ closure: @escaping ExternalMixedQuaternaryClosure
    ) -> ExternalMixedQuaternaryClosure
    func mixedQuinary(
        _ closure: @escaping ExternalMixedQuinaryClosure
    ) -> ExternalMixedQuinaryClosure
    func senary(
        _ closure: @escaping ExternalSenaryClosure
    ) -> ExternalSenaryClosure
    func throwingQuaternary(
        _ closure: @escaping ExternalThrowingQuaternaryClosure
    ) -> ExternalThrowingQuaternaryClosure
    func optionalHigherOrder(
        _ closure: @escaping ExternalOptionalHigherOrderClosure
    ) -> ExternalOptionalHigherOrderClosure
}

public struct RealExternalDynamicArityClosureService:
    ExternalDynamicArityClosureService
{
    public init() {}

    public func wideUnary(
        _ closure: @escaping ExternalWideUnaryClosure
    ) -> ExternalWideUnaryClosure { closure }

    public func mixedBinary(
        _ closure: @escaping ExternalMixedBinaryClosure
    ) -> ExternalMixedBinaryClosure { closure }

    public func mixedTernary(
        _ closure: @escaping ExternalMixedTernaryClosure
    ) -> ExternalMixedTernaryClosure { closure }

    public func mixedQuaternary(
        _ closure: @escaping ExternalMixedQuaternaryClosure
    ) -> ExternalMixedQuaternaryClosure { closure }

    public func mixedQuinary(
        _ closure: @escaping ExternalMixedQuinaryClosure
    ) -> ExternalMixedQuinaryClosure { closure }

    public func senary(
        _ closure: @escaping ExternalSenaryClosure
    ) -> ExternalSenaryClosure { closure }

    public func throwingQuaternary(
        _ closure: @escaping ExternalThrowingQuaternaryClosure
    ) -> ExternalThrowingQuaternaryClosure { closure }

    public func optionalHigherOrder(
        _ closure: @escaping ExternalOptionalHigherOrderClosure
    ) -> ExternalOptionalHigherOrderClosure { closure }
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public protocol ExternalDynamicTypedClosureService {
    func nullary(
        _ closure: @escaping ExternalTypedNullaryClosure
    ) -> ExternalTypedNullaryClosure
    func quaternary(
        _ closure: @escaping ExternalTypedQuaternaryClosure
    ) -> ExternalTypedQuaternaryClosure
    func mixedError(
        _ closure: @escaping ExternalMixedTypedBinaryClosure
    ) -> ExternalMixedTypedBinaryClosure
    func indirectSuccess(
        _ closure: @escaping ExternalTypedIndirectSuccessClosure
    ) -> ExternalTypedIndirectSuccessClosure
    func higherOrder(
        _ closure: @escaping ExternalTypedHigherOrderClosure
    ) -> ExternalTypedHigherOrderClosure
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public struct RealExternalDynamicTypedClosureService:
    ExternalDynamicTypedClosureService
{
    public init() {}

    public func nullary(
        _ closure: @escaping ExternalTypedNullaryClosure
    ) -> ExternalTypedNullaryClosure { closure }

    public func quaternary(
        _ closure: @escaping ExternalTypedQuaternaryClosure
    ) -> ExternalTypedQuaternaryClosure { closure }

    public func mixedError(
        _ closure: @escaping ExternalMixedTypedBinaryClosure
    ) -> ExternalMixedTypedBinaryClosure { closure }

    public func indirectSuccess(
        _ closure: @escaping ExternalTypedIndirectSuccessClosure
    ) -> ExternalTypedIndirectSuccessClosure { closure }

    public func higherOrder(
        _ closure: @escaping ExternalTypedHigherOrderClosure
    ) -> ExternalTypedHigherOrderClosure { closure }
}

public enum ExternalClosureChoice: Sendable {
    case transform(ExternalContainerClosure)
    case none
}

public typealias ExternalClosureResult = Result<
    ExternalContainerClosure,
    ExternalDynamicClosureError
>
public typealias ExternalResultHigherOrderClosure =
    @Sendable (ExternalClosureResult) -> ExternalClosureResult

public struct ExternalGenericClosureBox<Value: Sendable>: Sendable {
    public let value: Value

    public init(value: Value) {
        self.value = value
    }
}

public typealias ExternalBoxHigherOrderClosure =
    @Sendable (
        ExternalGenericClosureBox<ExternalContainerClosure>
    ) -> ExternalGenericClosureBox<ExternalContainerClosure>

public protocol ExternalClosureCollectionService {
    func dictionary(
        _ closures: [String: ExternalContainerClosure]
    ) -> [String: ExternalContainerClosure]
    func result(_ value: ExternalClosureResult) -> ExternalClosureResult
    func choice(_ value: ExternalClosureChoice) -> ExternalClosureChoice
}

public struct RealExternalClosureCollectionService:
    ExternalClosureCollectionService
{
    public init() {}

    public func dictionary(
        _ closures: [String: ExternalContainerClosure]
    ) -> [String: ExternalContainerClosure] { closures }

    public func result(_ value: ExternalClosureResult) -> ExternalClosureResult {
        value
    }

    public func choice(_ value: ExternalClosureChoice) -> ExternalClosureChoice {
        value
    }
}

public protocol ExternalResultHigherOrderClosureService {
    func transform(
        _ closure: @escaping ExternalResultHigherOrderClosure
    ) -> ExternalResultHigherOrderClosure
    func boxed(
        _ closure: @escaping ExternalBoxHigherOrderClosure
    ) -> ExternalBoxHigherOrderClosure
}

public struct RealExternalResultHigherOrderClosureService:
    ExternalResultHigherOrderClosureService
{
    public init() {}

    public func transform(
        _ closure: @escaping ExternalResultHigherOrderClosure
    ) -> ExternalResultHigherOrderClosure { closure }

    public func boxed(
        _ closure: @escaping ExternalBoxHigherOrderClosure
    ) -> ExternalBoxHigherOrderClosure { closure }
}
