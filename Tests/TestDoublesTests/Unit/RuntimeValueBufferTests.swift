import Testing
@testable import TestDoubles

private final class ValueBufferLifetimeToken {}

private struct ValueBufferOwnedValue {
    let token: ValueBufferLifetimeToken
}

@Suite struct RuntimeValueBufferTests {
    @Test func borrowedBitsRemainCallerOwned() {
        var value = 42
        withUnsafeMutablePointer(to: &value) { pointer in
            let buffer = ManagedValueBuffer(
                borrowingBitsOf: Int.self,
                at: UnsafeMutableRawPointer(pointer)
            )

            #expect(buffer.state == .borrowedBits)
            #expect(buffer.storage.load(as: Int.self) == 42)
        }
        #expect(value == 42)
    }

    @Test func initializedValueIsDestroyedExactlyOnce() {
        var token: ValueBufferLifetimeToken? = ValueBufferLifetimeToken()
        weak let weakToken = token
        let buffer = ManagedValueBuffer(type: ValueBufferOwnedValue.self)
        buffer.storage.assumingMemoryBound(to: ValueBufferOwnedValue.self)
            .initialize(to: ValueBufferOwnedValue(token: token!))
        buffer.markInitialized()
        token = nil

        #expect(weakToken != nil)
        buffer.destroyInitializedValue()
        #expect(buffer.state == .uninitialized)
        #expect(weakToken == nil)
    }

    @Test func initializedValueIsDestroyedWhenBufferLeavesScope() {
        var token: ValueBufferLifetimeToken? = ValueBufferLifetimeToken()
        weak let weakToken = token

        do {
            let buffer = ManagedValueBuffer(type: ValueBufferOwnedValue.self)
            buffer.storage.assumingMemoryBound(to: ValueBufferOwnedValue.self)
                .initialize(to: ValueBufferOwnedValue(token: token!))
            buffer.markInitialized()
            token = nil
            #expect(weakToken != nil)
        }

        #expect(weakToken == nil)
    }

    @Test func movedValueLeavesTransferredStorage() {
        let buffer = ManagedValueBuffer(type: Int.self)
        buffer.storage.assumingMemoryBound(to: Int.self).initialize(to: 42)
        buffer.markInitialized()

        let value = buffer.moveInitializedValue(as: Int.self)

        #expect(value == 42)
        #expect(buffer.state == .transferred)
    }
}
