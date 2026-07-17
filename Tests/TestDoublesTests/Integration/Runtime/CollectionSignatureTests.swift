import Testing
@testable import TestDoubles

// Internal, not private: automatic-discovery fixtures must keep their
// conformance records reachable in release builds.
protocol CollectionSignatureProbe {
    func digest(_ bytes: [UInt8]) -> [String: Int]
    func tags() -> Set<String>
}

struct RealCollectionSignatureProbe: CollectionSignatureProbe {
    func digest(_ bytes: [UInt8]) -> [String: Int] { ["count": bytes.count] }
    func tags() -> Set<String> { [] }
}

@Suite struct CollectionSignatureTests {
    @Test func discoveryHandlesCollectionSignatures() throws {
        let stub = try Stub<any CollectionSignatureProbe>()
        stub.when { $0.digest(equal([1, 2, 3])) }.thenReturn(["count": 3])
        stub.when { $0.tags() }.thenReturn(["fast", "unit"])

        let probe = stub()
        #expect(probe.digest([1, 2, 3]) == ["count": 3])
        #expect(probe.tags() == ["fast", "unit"])
        stub.verify(.exactly(1)) { $0.digest(any()) }
    }
}
