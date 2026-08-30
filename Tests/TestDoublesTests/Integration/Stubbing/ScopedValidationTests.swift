@_spi(Testing) import TestDoubles
import TestDoublesTesting
import Testing

@Suite struct ScopedValidationTests {
    private enum ExpectedFailure: Error, Equatable {
        case stopped
    }

    @Test func lexicalScopeReturnsSynchronousResult() {
        let result = TestDouble.withScope(checking: .strict) {
            let double = ClosureDouble<Int, Int>()
            let call = double.when(equal: 21).thenReturn(42)

            let result = double.function(21)
            call.verify()
            return result
        }

        #expect(result == 42)
    }

    @Test func lexicalScopeReturnsAsynchronousResult() async {
        let result = await TestDouble.withScope(checking: .strict) {
            let double = AsyncClosureDouble<Int, Int>()
            let call = double.when(equal: 21).thenReturn(42)

            let result = await double.function(21)
            call.verify()
            return result
        }

        #expect(result == 42)
    }

    @Test func lexicalScopePreservesThrownError() {
        #expect(throws: ExpectedFailure.stopped) {
            try TestDouble.withScope(checking: []) {
                throw ExpectedFailure.stopped
            }
        }
    }

    @Test func structuredChildTasksInheritScopeButDetachedTasksDoNot() async {
        await TestDouble.withScope(checking: []) {
            #expect(TestDoubleTestingContext.session != nil)
            #expect(await Task { TestDoubleTestingContext.session != nil }.value)
            #expect(await Task.detached { TestDoubleTestingContext.session == nil }.value)
        }
    }

    @Test func nestedLexicalScopesUseIndependentSessions() throws {
        try TestDouble.withScope(checking: []) {
            let outer = try #require(TestDoubleTestingContext.session)
            try TestDouble.withScope(checking: []) {
                let inner = try #require(TestDoubleTestingContext.session)
                #expect(inner !== outer)
            }
            #expect(TestDoubleTestingContext.session === outer)
        }
    }

    @Test func lifecyclePresetIncludesOnlyDeterministicResourceChecks() {
        let lifecycle = TestDoubleStrictness.lifecycle
        #expect(lifecycle.contains(.noUnconsumedBehaviorQueues))
        #expect(lifecycle.contains(.noPendingSuspensions))
        #expect(lifecycle.contains(.noPendingCallbackCaptures))
        #expect(lifecycle.contains(.noUnfinishedAsyncInvocations))
        #expect(lifecycle.contains(.noUnconsumedInvocationStreams))
        #expect(lifecycle.contains(.noOpenStreamControllers))
        #expect(lifecycle.contains(.noUnusedStubs) == false)
        #expect(lifecycle.contains(.noMoreInteractions) == false)
        #expect(lifecycle.contains(.noEscapedTestDoubles) == false)
    }

    @Test(.testDoubles(.lifecycle))
    func positionalTraitShorthandCompiles() {}
}
