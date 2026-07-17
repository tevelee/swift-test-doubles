import TestDoubles
import TestDoublesFixtures
import Testing

@Suite struct RuntimeClosureTests {
    @Test func externalProtocolClosureArgumentsAndResultsNeedNoRequirements() throws {
        _ = RealExternalClosureService()
        let identity: ExternalTransform = { $0 }
        let stub = try Stub<any ExternalClosureService>()
        stub.when(returning: identity) {
            $0.transform(any(using: identity))
        }.then { (body: ExternalTransform) in
            let captured = body(20) + 2
            return { _ in captured }
        }

        let result = stub().transform { $0 * 2 }
        #expect(result(0) == 42)
    }

    @Test func externalProtocolClosureCanBeOneOfSeveralArguments() throws {
        _ = RealExternalClosureService()
        let identity: ExternalTransform = { $0 }
        let stub = try Stub<any ExternalClosureService>()
        stub.when {
            $0.apply(any(using: identity), to: any())
        }.thenEscaping { (body: ExternalTransform, value: Int) in
            body(value) + 2
        }

        #expect(stub().apply({ $0 * 2 }, to: 20) == 42)
    }

    @Test func externalProtocolOrdinaryClosureGetterReturnsCapturedValue() throws {
        _ = RealExternalClosureService()
        let placeholder: ExternalFormatter = { $0 }
        let offset = 22
        let formatter: ExternalFormatter = { $0 + offset }
        let stub = try Stub<any ExternalClosureService>()
        stub.when(returning: placeholder) { $0.formatter }
            .thenReturn(formatter)

        #expect(stub().formatter(20) == 42)
    }
}
