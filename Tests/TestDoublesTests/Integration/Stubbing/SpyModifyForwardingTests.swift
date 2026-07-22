import TestDoubles
import Testing

protocol ModifyForwardingService {
    var value: Int { get set }
    subscript(index: Int) -> Int { get set }
}

final class ModifyForwardingTrace {
    var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

struct RealModifyForwardingService: ModifyForwardingService {
    let trace: ModifyForwardingTrace
    private var valueStorage = 10
    private var itemStorage = [3, 7]

    init(trace: ModifyForwardingTrace) {
        self.trace = trace
    }

    var value: Int {
        get {
            trace.append("value.get.\(valueStorage)")
            return valueStorage
        }
        set {
            trace.append("value.set.\(newValue)")
            valueStorage = newValue
        }
        _modify {
            trace.append("value.begin")
            defer { trace.append("value.end.\(valueStorage)") }
            yield &valueStorage
            trace.append("value.resume")
        }
    }

    subscript(index: Int) -> Int {
        get {
            trace.append("subscript.\(index).get.\(itemStorage[index])")
            return itemStorage[index]
        }
        set {
            trace.append("subscript.\(index).set.\(newValue)")
            itemStorage[index] = newValue
        }
        _modify {
            trace.append("subscript.\(index).begin")
            defer {
                trace.append("subscript.\(index).end.\(itemStorage[index])")
            }
            yield &itemStorage[index]
            trace.append("subscript.\(index).resume")
        }
    }
}

struct LargeModifyValue: Equatable {
    var first: UInt64
    var second: UInt64
    var third: UInt64
    var fourth: UInt64
}

protocol AssociatedModifyForwardingService<Value> {
    associatedtype Value
    var value: Value { get set }
}

struct RealAssociatedModifyForwardingService: AssociatedModifyForwardingService {
    let trace: ModifyForwardingTrace
    private var storage = LargeModifyValue(
        first: 1,
        second: 2,
        third: 3,
        fourth: 4
    )

    init(trace: ModifyForwardingTrace) {
        self.trace = trace
    }

    var value: LargeModifyValue {
        get {
            trace.append("associated.get.\(storage.first)")
            return storage
        }
        set {
            trace.append("associated.set.\(newValue.first)")
            storage = newValue
        }
        _modify {
            trace.append("associated.begin")
            defer { trace.append("associated.end.\(storage.first)") }
            yield &storage
            trace.append("associated.resume")
        }
    }
}

final class ModifyLifetimeReference {}

final class ModifyWeakReference {
    weak var value: ModifyLifetimeReference?

    init(_ value: ModifyLifetimeReference?) {
        self.value = value
    }
}

struct ModifyLifetimeValue {
    var reference: ModifyLifetimeReference?
    var count: Int
}

protocol ModifyLifetimeService {
    var value: ModifyLifetimeValue { get set }
}

struct RealModifyLifetimeService: ModifyLifetimeService {
    private var storage: ModifyLifetimeValue

    init(_ storage: ModifyLifetimeValue) {
        self.storage = storage
    }

    var value: ModifyLifetimeValue {
        get { storage }
        set { storage = newValue }
        _modify { yield &storage }
    }
}

private struct ModifyForwardingAbort: Error {}

@Suite struct SpyModifyForwardingTests {
    @Test func forwardsPropertyAndSubscriptMutationIntoTargetStorage() throws {
        let trace = ModifyForwardingTrace()
        let spy = try Spy<any ModifyForwardingService>(
            forwardingTo: RealModifyForwardingService(trace: trace)
        )
        var service: any ModifyForwardingService = spy()

        service.value += 2
        service[1] *= 3

        #expect(service.value == 12)
        #expect(service[1] == 21)
        #expect(
            trace.events
                == [
                    "value.begin", "value.resume", "value.end.12",
                    "subscript.1.begin", "subscript.1.resume",
                    "subscript.1.end.21", "value.get.12",
                    "subscript.1.get.21"
                ]
        )
        spy.verify(.exactly(2)) { $0.value }
        spy.verify(.exactly(2)) { $0[equal(1)] }
    }

    @Test func configuredGetterOverrideSkipsTargetModifyAndSetter() throws {
        let trace = ModifyForwardingTrace()
        let spy = try Spy<any ModifyForwardingService>(
            forwardingTo: RealModifyForwardingService(trace: trace)
        )
        spy.when { $0.value }.thenReturn(40)
        var service: any ModifyForwardingService = spy()

        service.value += 2

        #expect(trace.events.isEmpty)
        spy.verify(.exactly(1)) { $0.value }
        spy.verify(.exactly(1)) { $0.value = equal(42) }
    }

    @Test func forwardsAssociatedIndirectStorageAndPersistsMutation() throws {
        let trace = ModifyForwardingTrace()
        let spy = try Spy<any AssociatedModifyForwardingService<LargeModifyValue>>(
            forwardingTo: RealAssociatedModifyForwardingService(trace: trace)
        )
        var service: any AssociatedModifyForwardingService<LargeModifyValue> = spy()

        service.value.first = 42

        #expect(
            service.value
                == LargeModifyValue(
                    first: 42,
                    second: 2,
                    third: 3,
                    fourth: 4
                )
        )
        #expect(
            trace.events
                == [
                    "associated.begin", "associated.resume",
                    "associated.end.42", "associated.get.42"
                ]
        )
        spy.verify(.exactly(2)) { $0.value }
    }

    @Test func forwardsAbortAndResumesTargetExactlyOnce() throws {
        let trace = ModifyForwardingTrace()
        let spy = try Spy<any ModifyForwardingService>(
            forwardingTo: RealModifyForwardingService(trace: trace)
        )
        var service: any ModifyForwardingService = spy()

        #expect(throws: ModifyForwardingAbort.self) {
            try mutateThenAbort(&service.value)
        }

        #expect(service.value == 15)
        #expect(
            trace.events
                == ["value.begin", "value.end.15", "value.get.15"]
        )
        spy.verify(.exactly(2)) { $0.value }
    }

    @Test func retainsReferenceContainingTargetStorageUntilResume() throws {
        var reference: ModifyLifetimeReference? = ModifyLifetimeReference()
        let weakReference = ModifyWeakReference(reference)
        let spy = try Spy<any ModifyLifetimeService>(
            forwardingTo: RealModifyLifetimeService(
                ModifyLifetimeValue(reference: reference, count: 1)
            )
        )
        var service: any ModifyLifetimeService = spy()
        reference = nil

        clearReferenceAndIncrement(
            &service.value,
            weakReference: weakReference.value
        )

        #expect(weakReference.value == nil)
        #expect(service.value.count == 2)
        spy.verify(.exactly(2)) { $0.value }
    }
}

@inline(never)
private func mutateThenAbort(
    _ value: inout Int
) throws(ModifyForwardingAbort) {
    value += 5
    throw ModifyForwardingAbort()
}

@inline(never)
private func clearReferenceAndIncrement(
    _ value: inout ModifyLifetimeValue,
    weakReference: ModifyLifetimeReference?
) {
    #expect(weakReference != nil)
    value.reference = nil
    value.count += 1
}
