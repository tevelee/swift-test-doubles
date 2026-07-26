import Testing
@testable import TestDoublesRuntimeMetadata

@Suite struct RuntimeMethodProjectionTests {
    @Test func semanticProjectionPreservesDiagnosticSignaturesLazily() {
        let methods = [
            MethodDescriptor(
                kind: .getter,
                name: "subscript",
                index: 0,
                argumentTypes: [Int.self],
                returnType: String.self
            ),
            MethodDescriptor(
                kind: .setter,
                name: "subscript",
                index: 1,
                argumentTypes: [Int.self, String.self],
                returnType: Void.self
            ),
            MethodDescriptor(
                kind: .method,
                name: "transform",
                index: 2,
                argumentTypes: [[String: Int].self],
                returnType: String.self,
                argumentDependencies: [.dictionary(key: "Key", value: "Value")],
                typedErrorType: ProjectionError.self,
                typedErrorDependency: .associatedType(name: "Failure"),
                isThrowing: true
            )
        ]

        for method in methods {
            #expect(method.runtimeMethod.signatureDescription == method.signatureDescription)
        }
    }

    private enum ProjectionError: Error {}
}
