import Foundation

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

public protocol Modify2AccessorProbe {
    var value: Int { get set }
}

public struct LinkedModify2AccessorProbe: Modify2AccessorProbe {
    private var storage: Int

    public init(value: Int = 0) {
        storage = value
    }

    public var value: Int {
        get { storage }
        set { storage = newValue }
        _modify { yield &storage }
    }
}

public protocol ExplicitReadAccessorProbe {
    var value: Int { read }
}

public final class ReadLifetimeReference: @unchecked Sendable {
    public let value: Int

    public init(value: Int) {
        self.value = value
    }

    public func abortBorrow() throws(ReadForwardingAbortError) -> Never {
        throw ReadForwardingAbortError()
    }
}

public struct ReadForwardingAbortError: Error {
    public init() {}
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

public final class ReadForwardingTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []
    private weak var storedReference: ReadLifetimeReference?

    public init() {}

    public var events: [String] {
        lock.withLock { storedEvents }
    }

    public var borrowedReference: ReadLifetimeReference? {
        lock.withLock { storedReference }
    }

    public func record(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }

    public func observeBorrowedReference(_ reference: ReadLifetimeReference) {
        lock.withLock { storedReference = reference }
    }
}

public final class ForwardingConcreteReadAccessorProbe: ConcreteReadAccessorProbe {
    public let trace: ReadForwardingTrace

    public init(trace: ReadForwardingTrace) {
        self.trace = trace
    }

    public var integer: Int {
        read {
            trace.record("integer.begin")
            yield 7
            trace.record("integer.end")
        }
    }

    public var text: String {
        read {
            trace.record("text.begin")
            yield "forwarded"
            trace.record("text.end")
        }
    }

    public var dictionary: [String: Int] {
        read {
            trace.record("dictionary.begin")
            let value = ["forwarded": 42]
            yield value
            trace.record("dictionary.end")
        }
    }

    public subscript(_ index: Int) -> Int {
        read {
            trace.record("subscript.\(index).begin")
            yield index * 2
            trace.record("subscript.\(index).end")
        }
    }
}

public final class ForwardingAssociatedReadAccessorProbe:
    AssociatedReadAccessorProbe
{
    public let trace: ReadForwardingTrace

    public init(trace: ReadForwardingTrace) {
        self.trace = trace
    }

    public var value: Int {
        read {
            trace.record("associated.value.begin")
            yield 41
            trace.record("associated.value.end")
        }
    }

    public subscript(_ index: Int) -> Int {
        read {
            trace.record("associated.subscript.\(index).begin")
            yield index + 1
            trace.record("associated.subscript.\(index).end")
        }
    }
}

public final class ForwardingReadLifetimeProbe: ReadLifetimeProbe {
    public let trace: ReadForwardingTrace

    public init(trace: ReadForwardingTrace) {
        self.trace = trace
    }

    public var value: ReadLifetimeValue {
        read {
            let reference = ReadLifetimeReference(value: 42)
            trace.observeBorrowedReference(reference)
            trace.record("lifetime.begin")
            yield ReadLifetimeValue(reference: reference)
            trace.record("lifetime.end")
        }
    }
}
