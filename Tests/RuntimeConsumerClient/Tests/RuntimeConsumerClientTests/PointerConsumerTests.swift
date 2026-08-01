import ConsumerFixtures
import TestDoubles
import Testing

@Suite struct PointerConsumerTests {
    @Test func typedUnsafePointerArgumentsResolveInAnOrdinaryConsumer() throws {
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        pointer.pointee = 42

        let stub = try Stub<any ByteReader>()
        stub.when { $0.read(Match.any(using: UnsafePointer(pointer))) }
            .then { (pointer: UnsafePointer<UInt8>) in pointer.pointee }

        #expect(stub().read(UnsafePointer(pointer)) == 42)
    }

    @Test func typedUnsafeBufferArgumentsResolveInAnOrdinaryConsumer() throws {
        let bytes: [UInt8] = [2, 3, 5]
        try bytes.withUnsafeBufferPointer { buffer in
            let stub = try Stub<any ByteBufferReader>()
            stub.when { $0.sum(Match.any(using: buffer)) }
                .then { (buffer: UnsafeBufferPointer<UInt8>) in
                    buffer.reduce(0) { $0 + UInt($1) }
                }

            let actual = stub().sum(buffer)
            #expect(actual == 10)
        }
    }
}
