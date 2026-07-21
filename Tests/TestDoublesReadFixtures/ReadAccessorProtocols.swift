public protocol ConcreteReadAccessorProbe {
    var integer: Int { read }
    var text: String { read }
    var dictionary: [String: Int] { read }
    subscript(_ index: Int) -> Int { read }
}

public struct LinkedConcreteReadAccessorProbe: ConcreteReadAccessorProbe {
    public init() {}

    public var integer: Int { read { yield 0 } }
    public var text: String { read { yield "linked" } }
    public var dictionary: [String: Int] {
        read {
            let value = ["linked": 0]
            yield value
        }
    }
    public subscript(_ index: Int) -> Int { read { yield index } }
}

public protocol AssociatedReadAccessorProbe<Value> {
    associatedtype Value
    var value: Value { read }
    subscript(_ index: Int) -> Value { read }
}

public struct LinkedAssociatedReadAccessorProbe: AssociatedReadAccessorProbe {
    public init() {}

    public var value: Int { read { yield 0 } }
    public subscript(_ index: Int) -> Int { read { yield index } }
}

public protocol ExplicitReadAccessorProbe {
    var value: Int { read }
}

public final class ReadLifetimeReference: @unchecked Sendable {
    public let value: Int

    public init(value: Int) {
        self.value = value
    }
}

public struct ReadLifetimeValue: @unchecked Sendable {
    public let reference: ReadLifetimeReference

    public init(reference: ReadLifetimeReference) {
        self.reference = reference
    }
}

public protocol ReadLifetimeProbe {
    var value: ReadLifetimeValue { read }
}

public struct LinkedReadLifetimeProbe: ReadLifetimeProbe {
    public init() {}

    public var value: ReadLifetimeValue {
        read { yield ReadLifetimeValue(reference: ReadLifetimeReference(value: 0)) }
    }
}
