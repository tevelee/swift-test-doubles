import Testing
import TestDoubles

protocol UntypedKeyValueStore: AnyObject {
    func value(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func object(forKey key: String) -> AnyObject?
    func values() -> [String: Any]
    func anything() -> Any
}

final class LiveUntypedKeyValueStore: UntypedKeyValueStore {
    func value(forKey key: String) -> Any? { nil }
    func set(_ value: Any?, forKey key: String) {}
    func object(forKey key: String) -> AnyObject? { nil }
    func values() -> [String: Any] { [:] }
    func anything() -> Any { 0 }
}

private final class StoredObject {}

/// `Any` and `AnyObject` inside discovered signatures resolve to their
/// runtime metadata, as in a UserDefaults-style store, and an `Optional` of
/// an opaque existential is passed and returned indirectly.
@Suite struct OpaqueExistentialValueTests {
    @Test func anyAndAnyObjectSignaturesAreDiscovered() throws {
        let store = try Stub<any UntypedKeyValueStore>(
            discoveringFrom: LiveUntypedKeyValueStore()
        )
        let object = StoredObject()
        store.when { $0.value(forKey: "name") }.thenReturn("Blob")
        store.when { $0.value(forKey: Match.any()) }.thenReturn(nil)
        let sets = store.when { $0.set(Match.any(), forKey: Match.any()) }
        sets.thenDoNothing()
        store.when { $0.object(forKey: Match.any()) }.thenReturn(object)
        store.when { $0.values() }.thenReturn(["count": 3])
        store.when { $0.anything() }.thenReturn("value")

        let service = store()
        service.set(5, forKey: "launches")

        #expect(service.value(forKey: "name") as? String == "Blob")
        #expect(service.value(forKey: "missing") == nil)
        #expect(service.object(forKey: "x") === object)
        #expect(service.values()["count"] as? Int == 3)
        #expect(service.anything() as? String == "value")
        let recorded: [(Any?, String)] = sets.arguments()
        #expect(recorded.first?.0 as? Int == 5)
        #expect(recorded.first?.1 == "launches")
    }
}
