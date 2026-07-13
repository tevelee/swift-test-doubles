#if RUNTIME_STUB
import Testing
@testable import TestDoubles

struct SlotTests {
    @Test func methodReferenceSupportsArityBeyondPreviousLimit() throws {
        let reference: (Int, String, Bool, Double, UInt, Float, Character) -> Void = {
            _, _, _, _, _, _, _ in
        }

        let slot = Slot.from(reference)
        let argumentTypes = try #require(slot.argumentTypes)

        #expect(slot.signature.args == [
            "Swift.Int",
            "Swift.String",
            "Swift.Bool",
            "Swift.Double",
            "Swift.UInt",
            "Swift.Float",
            "Swift.Character",
        ])
        #expect(argumentTypes.map(ObjectIdentifier.init) == [
            ObjectIdentifier(Int.self),
            ObjectIdentifier(String.self),
            ObjectIdentifier(Bool.self),
            ObjectIdentifier(Double.self),
            ObjectIdentifier(UInt.self),
            ObjectIdentifier(Float.self),
            ObjectIdentifier(Character.self),
        ])
        #expect(slot.signature.ret == "Swift.Void")
    }

    @Test func methodReferencesPreserveEffects() {
        let synchronous: () -> Int = { 0 }
        let throwing: () throws -> Int = { 0 }
        let asynchronous: () async -> Int = { 0 }
        let asynchronousThrowing: () async throws -> Int = { 0 }

        let synchronousSlot = Slot.from(synchronous)
        let throwingSlot = Slot.from(throwing)
        let asynchronousSlot = Slot.from(asynchronous)
        let asynchronousThrowingSlot = Slot.from(asynchronousThrowing)

        #expect(synchronousSlot.isThrowing == false)
        #expect(synchronousSlot.isAsync == false)
        #expect(throwingSlot.isThrowing)
        #expect(throwingSlot.isAsync == false)
        #expect(asynchronousSlot.isThrowing == false)
        #expect(asynchronousSlot.isAsync)
        #expect(asynchronousThrowingSlot.isThrowing)
        #expect(asynchronousThrowingSlot.isAsync)
    }
}
#endif // RUNTIME_STUB
