import InternalRuntimeContract
import Testing
@testable import TestDoubles

@Suite("Dummy invocation diagnostics")
struct DummyInvocationTests {
    @Test func describesKnownAndUnknownWitnessSlots() {
        let invocation = DummyInvocationEndpoint(
            typeDescription: "any ExampleService",
            requirements: [
                RuntimeDummyRequirement(
                    slot: 3,
                    description: "ExampleService method requirement at witness index 5"
                )
            ]
        )

        let known = invocation.rejectionMessage(slot: 3)
        let unknown = invocation.rejectionMessage(slot: 9)

        #expect(known.contains("Dummy<any ExampleService>"))
        #expect(known.contains("ExampleService method requirement at witness index 5"))
        #expect(
            known.contains("A dummy may only be passed to code paths that do not use it")
        )
        #expect(known.contains("replace the dummy with `Stub`, `CompiledStub`, or a hand-written fake"))
        #expect(unknown.contains("unknown requirement at dispatch slot 9"))
    }
}
