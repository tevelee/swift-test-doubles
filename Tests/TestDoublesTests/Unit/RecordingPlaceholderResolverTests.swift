import Foundation
import Testing
@testable import TestDoubles

private final class RegisteredResultValue {
    let identifier: Int

    init(identifier: Int) {
        self.identifier = identifier
    }
}

private final class UnsupportedResultValue {}

private enum SynthesizableResultFailure: Error {
    case fallback
}

@Suite struct RecordingPlaceholderResolverTests {
    @Test func resultUsesASynthesizedSuccessValue() throws {
        let placeholder = try #require(
            RecordingPlaceholderResolver.make(Result<Int, Never>.self)
        )

        switch placeholder {
            case .success(let value):
                #expect(value == 0)
            case .failure(let impossible):
                switch impossible {}
        }
    }

    @Test func resultRecursivelyBuildsFoundationAndOptionalPayloads() throws {
        let placeholder = try #require(
            RecordingPlaceholderResolver.make(
                Result<URL?, SynthesizableResultFailure>.self
            )
        )

        switch placeholder {
            case .success(.some(let value)):
                #expect(value.path() == "/test-doubles-placeholder")
            case .success(.none), .failure:
                Issue.record("Expected a populated URL success placeholder.")
        }
    }

    @Test func resultFallsBackToASynthesizedFailure() throws {
        let placeholder = try #require(
            RecordingPlaceholderResolver.make(
                Result<UnsupportedResultValue, SynthesizableResultFailure>.self
            )
        )

        switch placeholder {
            case .success:
                Issue.record("Expected the failure payload fallback.")
            case .failure(.fallback):
                break
        }
    }

    @Test func resultUsesARegisteredNestedSuccessFactory() throws {
        Match.Placeholders.register {
            RegisteredResultValue(identifier: 42)
        }
        defer { Match.Placeholders.unregister(RegisteredResultValue.self) }

        let placeholder = try #require(
            RecordingPlaceholderResolver.make(
                Result<RegisteredResultValue, Never>.self
            )
        )

        switch placeholder {
            case .success(let value):
                #expect(value.identifier == 42)
            case .failure(let impossible):
                switch impossible {}
        }
    }

    @Test func resultWithoutAConstructiblePayloadRemainsUnsupported() {
        let placeholder = RecordingPlaceholderResolver.make(
            Result<UnsupportedResultValue, Never>.self
        )

        #expect(placeholder == nil)
    }
}
