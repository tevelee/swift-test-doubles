import TestDoubles

// This is deliberately an ordinary direct-witness requirement: it verifies
// Android can allocate and publish the executable veneer, fabricate the
// existential storage, invoke the generated witness, and record the call.
// Use the public signatureOf: factory so the release executable has no
// accidental dependency on a live conformer surviving dead stripping.
protocol AndroidRuntimeDemoService {
    func doubled(_ value: Int) -> Int
}

func demonstrateRuntimeStub() throws {
    let stub = try Stub<any AndroidRuntimeDemoService>(
        .method(signatureOf: AndroidRuntimeDemoService.doubled)
    )
    stub.onCall { $0.doubled(Match.equal(21)) }.thenReturn(42)

    let service: any AndroidRuntimeDemoService = stub()
    precondition(service.doubled(21) == 42)
    stub.verify(.exactly(1)) { $0.doubled(Match.equal(21)) }
}

try demonstrateRuntimeStub()
print("AndroidRuntimeDemo: fabricated Stub invocation passed.")
