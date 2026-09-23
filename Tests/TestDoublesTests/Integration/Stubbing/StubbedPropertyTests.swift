import Testing
import TestDoubles

protocol StubbedPropertySettings: AnyObject {
    var username: String? { get set }
    var fontSize: Double { get set }
}

final class LiveStubbedPropertySettings: StubbedPropertySettings {
    var username: String?
    var fontSize = 14.0
}

protocol StubbedPropertyCounter {
    var count: Int { get set }
}

struct LiveStubbedPropertyCounter: StubbedPropertyCounter {
    var count = 0
}

private struct StubbedPropertyCounterStubConformer: StubbedPropertyCounter, ManualStubConformer {
    let stub: CompiledStub<Self>

    var count: Int {
        get { stub.call() }
        nonmutating set { stub.call(newValue) }
    }
}

/// `whenProperty` makes a read-write requirement behave like stored state
/// while still recording every access.
@Suite struct StubbedPropertyTests {
    @Test func classBoundPropertiesStoreAssignedValues() throws {
        let settings = try Stub<any StubbedPropertySettings>(
            discoveringFrom: LiveStubbedPropertySettings()
        )
        let username = settings.whenProperty(
            initialValue: nil,
            get: { $0.username },
            set: { $0.username = $1 }
        )
        let fontSize = settings.whenProperty(
            initialValue: 12,
            get: { $0.fontSize },
            set: { $0.fontSize = $1 }
        )
        let service = settings()

        #expect(service.username == nil)
        service.username = "blob"
        service.fontSize = 18

        #expect(service.username == "blob")
        #expect(service.fontSize == 18)
        #expect(username.value == "blob")
        username.setter.verify()
        username.getter.verify(2 ... 2)
        fontSize.value = 20
        #expect(service.fontSize == 20)
    }

    @Test func valuePropertiesStoreAssignedValues() throws {
        let counter = try Stub<any StubbedPropertyCounter>(
            discoveringFrom: LiveStubbedPropertyCounter()
        )
        let count = counter.whenProperty(
            initialValue: 1,
            get: { $0.count },
            set: { $0.count = $1 }
        )
        var service = counter()

        service.count = 5
        service.count += 1

        #expect(service.count == 6)
        #expect(count.value == 6)
        count.setter.verify(2 ... 2)
    }

    @Test func compiledConformersStoreAssignedValues() {
        let counter = CompiledStub<StubbedPropertyCounterStubConformer>()
        let count = counter.whenProperty(
            initialValue: 3,
            get: { $0.count },
            set: { $0.count = $1 }
        )
        let service = counter()

        service.count = 9

        #expect(service.count == 9)
        count.getter.verify()
        count.setter.verify()
    }
}
