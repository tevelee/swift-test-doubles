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

private final class UnsupportedResultFailure: Error {}

private enum SynthesizableResultFailure: Error {
    case fallback
}

private typealias ScopedPrecedenceValue = Result<StaticString, Never>

private struct ScopedAsyncValue: Sendable, Equatable {
    let marker: Int
}

private struct NestedScopedValue: Sendable, Equatable {
    let marker: Int
}

private struct OtherNestedScopedValue: Sendable, Equatable {
    let marker: Int
}

private typealias InheritedScopedValue = Result<AnyHashable, Never>

private struct ExplicitScopedValue: Sendable, Equatable {
    let marker: Int
}

private class ExactScopedBase: @unchecked Sendable {}
private final class ExactScopedChild: ExactScopedBase, @unchecked Sendable {}

private enum PlaceholderScopeFailure: Error {
    case expected
}

private func scopedPrecedenceMarker(_ value: ScopedPrecedenceValue?) -> String? {
    guard let value else { return nil }
    switch value {
        case .success(let marker):
            return marker.description
        case .failure(let impossible):
            switch impossible {}
    }
}

private func inheritedScopedMarker() -> Int? {
    guard let value = RecordingPlaceholderResolver.make(InheritedScopedValue.self) else {
        return nil
    }
    switch value {
        case .success(let marker):
            return marker.base as? Int
        case .failure(let impossible):
            switch impossible {}
    }
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
                Result<URL?, any Error>.self
            )
        )

        switch placeholder {
            case .success(.some(let value)):
                #expect(value.path() == "/test-doubles-placeholder")
            case .success(.none), .failure:
                Issue.record("Expected a populated URL success placeholder.")
        }
    }

    @Test func resultUsesAFoundationLeafBeforeAnExistentialError() throws {
        let placeholder = try #require(
            RecordingPlaceholderResolver.make(Result<URL, any Error>.self)
        )

        switch placeholder {
            case .success(let value):
                #expect(value.path() == "/test-doubles-placeholder")
            case .failure:
                Issue.record("Expected the Foundation success placeholder.")
        }
    }

    @Test func optionalResultRecursivelyBuildsEveryWrapper() throws {
        let optional = try #require(
            RecordingPlaceholderResolver.make(
                Optional<Result<URL, any Error>>.self
            )
        )
        let placeholder = try #require(optional)

        switch placeholder {
            case .success(let value):
                #expect(value.path() == "/test-doubles-placeholder")
            case .failure:
                Issue.record("Expected the nested Foundation success placeholder.")
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
            Result<UnsupportedResultValue, UnsupportedResultFailure>.self
        )

        #expect(placeholder == nil)
    }

    @Test func lexicalFactoryOverridesGlobalAndSynthesizedPlaceholders() {
        #expect(
            scopedPrecedenceMarker(RecordingPlaceholderResolver.make(ScopedPrecedenceValue.self))
                == "test-doubles-placeholder"
        )

        Match.Placeholders.register { ScopedPrecedenceValue.success("global") }
        defer { Match.Placeholders.unregister(ScopedPrecedenceValue.self) }
        #expect(
            scopedPrecedenceMarker(RecordingPlaceholderResolver.make(ScopedPrecedenceValue.self))
                == "global"
        )

        let scoped = Match.Placeholders.withFactory({ ScopedPrecedenceValue.success("scoped") }) {
            RecordingPlaceholderResolver.make(ScopedPrecedenceValue.self)
        }

        #expect(scopedPrecedenceMarker(scoped) == "scoped")
        #expect(
            scopedPrecedenceMarker(RecordingPlaceholderResolver.make(ScopedPrecedenceValue.self))
                == "global"
        )

        Match.Placeholders.unregister(ScopedPrecedenceValue.self)
        #expect(
            scopedPrecedenceMarker(RecordingPlaceholderResolver.make(ScopedPrecedenceValue.self))
                == "test-doubles-placeholder"
        )
    }

    @Test func asynchronousLexicalFactorySurvivesSuspension() async {
        let scoped = await Match.Placeholders.withFactory({
            ScopedAsyncValue(marker: 42)
        }) {
            await Task.yield()
            return RecordingPlaceholderResolver.make(ScopedAsyncValue.self)
        }

        #expect(scoped?.marker == 42)
        #expect(Match.Placeholders.make(ScopedAsyncValue.self) == nil)
    }

    @Test func nestedLexicalFactoriesOverrideAndRestoreByExactType() {
        let values = Match.Placeholders.withFactory({ NestedScopedValue(marker: 1) }) {
            let before = RecordingPlaceholderResolver.make(NestedScopedValue.self)?.marker
            let nested = Match.Placeholders.withFactory({ NestedScopedValue(marker: 2) }) {
                Match.Placeholders.withFactory({ OtherNestedScopedValue(marker: 3) }) {
                    (
                        sameType: RecordingPlaceholderResolver.make(NestedScopedValue.self)?.marker,
                        otherType: RecordingPlaceholderResolver.make(OtherNestedScopedValue.self)?
                            .marker
                    )
                }
            }
            let after = RecordingPlaceholderResolver.make(NestedScopedValue.self)?.marker
            return (before: before, nested: nested, after: after)
        }

        #expect(values.before == 1)
        #expect(values.nested.sameType == 2)
        #expect(values.nested.otherType == 3)
        #expect(values.after == 1)
    }

    @Test func structuredChildrenInheritScopeButDetachedTasksDoNot() async {
        let values = await Match.Placeholders.withFactory({
            InheritedScopedValue.success(AnyHashable(7))
        }) {
            async let inherited: Int? = {
                await Task.yield()
                return inheritedScopedMarker()
            }()
            let detached = await Task.detached {
                inheritedScopedMarker()
            }.value
            return (inherited: await inherited, detached: detached)
        }

        #expect(values.inherited == 7)
        #expect(values.detached == 0)
    }

    @Test func taskScopedFactoriesMatchOnlyTheirExactType() {
        let child = ExactScopedChild()

        Match.Placeholders.withFactory({ child }) {
            #expect(RecordingPlaceholderResolver.make(ExactScopedChild.self) === child)
            #expect(RecordingPlaceholderResolver.make(ExactScopedBase.self) == nil)
        }
    }

    @Test func explicitUsingPlaceholderWinsWithoutInvokingTheScopedFactory() {
        let counter = LockedCounter()
        let explicit = ExplicitScopedValue(marker: 2)

        let resolved = Match.Placeholders.withFactory({
            counter.increment()
            return ExplicitScopedValue(marker: 1)
        }) {
            Match.any(using: explicit)
        }

        #expect(resolved == explicit)
        #expect(counter.value == 0)
    }

    @Test func lexicalFactoriesPreserveTypedThrows() async {
        #expect(throws: PlaceholderScopeFailure.expected) {
            try Match.Placeholders.withFactory({ ScopedPrecedenceValue.success("failure") }) {
                throw PlaceholderScopeFailure.expected
            }
        }

        await #expect(throws: PlaceholderScopeFailure.expected) {
            try await Match.Placeholders.withFactory({ ScopedAsyncValue(marker: 1) }) {
                await Task.yield()
                throw PlaceholderScopeFailure.expected
            }
        }
    }
}
