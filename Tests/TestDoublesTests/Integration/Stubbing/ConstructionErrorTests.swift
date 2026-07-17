import Testing
@testable import TestDoubles
import TestDoublesFixtures

@Suite struct ConstructionErrorTests {
    @Test func automaticConstructionRequiresLinkedConformance() {
        expectStubError({
            _ = try Stub<any PrototypeCalculator>()
        }) { error in
            guard case .noConformanceFound(let protocolName) = error else {
                return false
            }
            return protocolName == "PrototypeCalculator"
                && error.description.contains("found neither a linked conformer")
                && error.description.contains("Pass explicit `Stub.Requirement` values")
        }
    }

    @Test func rejectsWrongRequirementCount() {
        expectStubError({
            _ = try Stub<any PrototypeCalculator>(
                .method(Int.self, Int.self, returning: Int.self)
            )
        }) { error in
            guard
                case .requirementCountMismatch(let protocolName, let expected, let actual) = error
            else {
                return false
            }
            return protocolName == "PrototypeCalculator" && expected == 3 && actual == 1
        }
    }

    @Test func rejectsWrongRequirementKind() {
        expectStubError({
            _ = try Stub<any PrototypeCalculator>(
                .getter(Int.self),
                .method(Int.self, returning: String.self),
                .getter(Int.self)
            )
        }) { error in
            guard
                case .requirementMismatch(let protocolName, let index, let expected, let actual) =
                    error
            else {
                return false
            }
            return protocolName == "PrototypeCalculator"
                && index == 0
                && expected == "method"
                && actual == "getter"
        }
    }

    @Test func rejectsNonProtocolTypes() {
        expectStubError({
            _ = try Stub<Int>()
        }) { error in
            guard case .typeIsNotProtocol = error else { return false }
            return true
        }
    }
}
