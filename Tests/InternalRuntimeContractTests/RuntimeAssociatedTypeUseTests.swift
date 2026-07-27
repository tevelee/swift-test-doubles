import InternalRuntimeContract
import Testing

@Suite struct RuntimeAssociatedTypeUseTests {
    @Test func retainsOrderedNamesOnlyAndProjectsThemIntoMethodDiagnostics() {
        let associatedTypeUse = RuntimeAssociatedTypeUse(
            names: ["Element", "Failure", "Element"]
        )
        let method = RuntimeMethod(
            kind: .method,
            receiver: .instance,
            origin: .automatic,
            name: "result()",
            slot: 0,
            arguments: [],
            result: RuntimeValue(
                type: String.self,
                convention: .concrete,
                associatedTypeUse: associatedTypeUse
            ),
            typedErrorType: nil,
            typedErrorAssociatedTypeUse: nil,
            selfIsClassConstrained: false,
            isThrowing: false,
            isAsync: false,
            hasReliableThrowing: true
        )

        #expect(associatedTypeUse.names == ["Element", "Failure"])
        #expect(associatedTypeUse.isDependent)
        #expect(method.returnAssociatedTypeUse == associatedTypeUse)
        #expect(
            method.signatureDescription
                == "method () -> Swift.String [associated Element, Failure]"
        )
    }
}
