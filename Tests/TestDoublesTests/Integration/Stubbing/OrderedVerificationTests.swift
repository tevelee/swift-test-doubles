import IssueReporting
import Testing
import TestDoubles

protocol OrderedVerificationProbe {
    func first(_ value: Int) -> Int
    func second(_ value: Int) -> Int
    func third(_ value: Int) -> Int
    func throwing(_ value: Int) throws -> Int
    func asynchronous(_ value: Int) async -> Int
    func asynchronousThrowing(_ value: Int) async throws -> Int
    var value: Int { get set }
}

struct RealOrderedVerificationProbe: OrderedVerificationProbe {
    func first(_ value: Int) -> Int { value }
    func second(_ value: Int) -> Int { value }
    func third(_ value: Int) -> Int { value }
    func throwing(_ value: Int) throws -> Int { value }
    func asynchronous(_ value: Int) async -> Int { value }
    func asynchronousThrowing(_ value: Int) async throws -> Int { value }
    var value: Int = 0
}

private func makeOrderedVerificationStub() throws -> Stub<any OrderedVerificationProbe> {
    try Stub<any OrderedVerificationProbe>(
        .method(Int.self, returning: Int.self),
        .method(Int.self, returning: Int.self),
        .method(Int.self, returning: Int.self),
        .method(Int.self, returning: Int.self, isThrowing: true),
        .method(Int.self, returning: Int.self, isAsync: true),
        .method(Int.self, returning: Int.self, isThrowing: true, isAsync: true),
        .getter(Int.self),
        .setter(Int.self)
    )
}

@Suite struct OrderedVerificationTests {
    @Test func matchesRelativeSubsequenceWithPerInvocationMatchers() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.second(Match.any()) }.thenReturn(0)
        stub.onCall { $0.third(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()

        _ = probe.first(1)
        _ = probe.third(99)
        _ = probe.second(2)
        _ = probe.first(3)

        stub.verifyInOrder {
            _ = $0.first(Match.equal(1))
            _ = $0.second(Match.equal(2))
            _ = $0.first(Match.equal(3))
        }

        // Ordered verification is a read-only query and does not weaken count
        // verification or consume any recorded calls.
        stub.verify(.exactly(2)) { $0.first(Match.any()) }
        stub.verifyInOrder {
            _ = $0.first(Match.equal(1))
            _ = $0.second(Match.equal(2))
        }
    }

    @Test func matchesTheCompleteTimelineWithoutExtraCalls() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.second(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = probe.first(1)
        _ = probe.second(2)

        stub.verifyExactlyInOrder {
            _ = $0.first(Match.equal(1))
            _ = $0.second(Match.equal(2))
        }
    }

    @Test func exactTimelineReportsExtraCalls() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.second(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = probe.first(1)
        _ = probe.second(2)

        expectReportsIssue {
            stub.verifyExactlyInOrder {
                _ = $0.first(Match.equal(1))
            }
        } matching: {
            $0.description.contains("exact interaction timeline")
                && $0.description.contains("Recorded 2 interactions")
        }
    }

    @Test func reversedOrderReportsAtTheCallerWithoutTerminating() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.second(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = probe.first(1)
        _ = probe.second(2)

        let expectedLine = UInt(#line + 2)
        expectReportsIssue {
            stub.verifyInOrder {
                _ = $0.second(Match.any())
                _ = $0.first(Match.any())
            }
        } matching: { issue in
            issue.description.contains("expectation 2")
                && issue.description.contains("Recorded call order")
                && String(describing: issue.fileID) == String(describing: #fileID)
                && String(describing: issue.filePath) == String(describing: #filePath)
                && issue.line == expectedLine
                && issue.column > 0
        }

        stub.verify(.exactly(1)) { $0.first(Match.any()) }
    }

    @Test func repeatedExpectationsConsumeDistinctCalls() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = probe.first(1)

        expectReportsIssue {
            stub.verifyInOrder {
                _ = $0.first(Match.any())
                _ = $0.first(Match.any())
            }
        } matching: {
            $0.description.contains("expectation 2")
        }

        _ = probe.first(2)
        stub.verifyInOrder {
            _ = $0.first(Match.any())
            _ = $0.first(Match.any())
        }
    }

    @Test func captorsCommitOnlyAfterTheEntireSequenceMatches() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.second(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = probe.first(7)
        let values = Match.Capture<Int>()

        expectReportsIssue {
            stub.verifyInOrder {
                _ = $0.first(values.capture())
                _ = $0.second(Match.any())
            }
        } matching: {
            $0.description.contains("expectation 2")
        }
        #expect(values.values.isEmpty)

        _ = probe.second(9)
        stub.verifyInOrder {
            _ = $0.first(values.capture())
            _ = $0.second(Match.any())
        }
        #expect(values.values == [7])
    }

    @Test func emptySequenceReportsWithoutTerminating() throws {
        let stub = try makeOrderedVerificationStub()

        expectReportsIssue {
            stub.verifyInOrder { _ in }
        } matching: {
            $0.description.contains("requires at least one invocation")
        }
    }

    @Test func mutatingSequenceSupportsMixedMethodsGettersAndSetters() throws {
        let stub = try makeOrderedVerificationStub()
        let setterExecutions = LockedCounter()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.value }.thenReturn(7)
        stub.onCall { $0.value = Match.any() }.then { (_: Int) in
            setterExecutions.increment()
        }
        stub.onCall { $0.second(Match.any()) }.thenReturn(0)
        var probe: any OrderedVerificationProbe = stub()

        _ = probe.first(1)
        probe.value = 2
        _ = probe.value
        _ = probe.second(3)

        stub.verifyInOrder(mutating: {
            _ = $0.first(Match.equal(1))
            $0.value = Match.equal(2)
            _ = $0.value
            _ = $0.second(Match.equal(3))
        })

        // Ordered verification remains a read-only query.
        stub.verify(.exactly(1)) { $0.value = Match.equal(2) }
        stub.verifyInOrder(mutating: {
            $0.value = Match.equal(2)
            _ = $0.value
        })
        #expect(setterExecutions.value == 1)
    }

    @Test func exactMutatingSequenceRejectsUnlistedInteractions() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.value = Match.any() }.thenDoNothing()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        var probe: any OrderedVerificationProbe = stub()
        probe.value = 1
        _ = probe.first(2)

        stub.verifyExactlyInOrder(mutating: {
            $0.value = Match.equal(1)
            _ = $0.first(Match.equal(2))
        })
    }

    @Test func mutatingSequenceReportsSetterOrderFailuresAtTheCaller() throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        stub.onCall { $0.value = Match.any() }.thenDoNothing()
        var probe: any OrderedVerificationProbe = stub()
        _ = probe.first(1)
        probe.value = 2
        let values = Match.Capture<Int>()

        let expectedLine = UInt(#line + 2)
        expectReportsIssue {
            stub.verifyInOrder(mutating: {
                $0.value = values.capture()
                _ = $0.first(Match.equal(1))
            })
        } matching: { issue in
            issue.description.contains("expectation 2")
                && issue.description.contains("Recorded call order")
                && String(describing: issue.fileID) == String(describing: #fileID)
                && String(describing: issue.filePath) == String(describing: #filePath)
                && issue.line == expectedLine
                && issue.column > 0
        }
        #expect(values.values.isEmpty)

        stub.verify(.exactly(1)) { $0.value = Match.equal(2) }
    }

    @Test func synchronousAndSuspendingHandlersAreNotReplayed() async throws {
        let stub = try makeOrderedVerificationStub()
        let synchronousExecutions = LockedCounter()
        let asynchronousExecutions = LockedCounter()
        stub.onCall { $0.first(Match.any()) }.then { (value: Int) in
            synchronousExecutions.increment()
            return value
        }
        await stub.onCall { await $0.asynchronous(Match.any()) }.then {
            (value: Int) async throws -> Int in
            asynchronousExecutions.increment()
            await Task.yield()
            return value
        }
        let probe: any OrderedVerificationProbe = stub()

        _ = probe.first(1)
        _ = await probe.asynchronous(2)

        await stub.verifyInOrder {
            _ = $0.first(Match.any())
            _ = await $0.asynchronous(Match.any())
        }
        #expect(synchronousExecutions.value == 1)
        #expect(asynchronousExecutions.value == 1)
    }

    @Test func asyncSequenceSupportsSynchronousAndThrowingRequirements() async throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { try $0.throwing(Match.any()) }.thenReturn(0)
        await stub.onCall { await $0.asynchronous(Match.any()) }.thenReturn(0)
        await stub.onCall { try await $0.asynchronousThrowing(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()

        _ = try probe.throwing(1)
        _ = await probe.asynchronous(2)
        _ = try await probe.asynchronousThrowing(3)

        await stub.verifyInOrder {
            _ = try $0.throwing(Match.equal(1))
            _ = await $0.asynchronous(Match.equal(2))
            _ = try await $0.asynchronousThrowing(Match.equal(3))
        }
    }

    @Test func exactAsyncSequenceRejectsUnlistedInteractions() async throws {
        let stub = try makeOrderedVerificationStub()
        stub.onCall { $0.first(Match.any()) }.thenReturn(0)
        await stub.onCall { await $0.asynchronous(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = probe.first(1)
        _ = await probe.asynchronous(2)

        await stub.verifyExactlyInOrder {
            _ = $0.first(Match.equal(1))
            _ = await $0.asynchronous(Match.equal(2))
        }
    }

    @Test func asynchronousFailureReportsAtTheCaller() async throws {
        let stub = try makeOrderedVerificationStub()
        await stub.onCall { await $0.asynchronous(Match.any()) }.thenReturn(0)
        let probe: any OrderedVerificationProbe = stub()
        _ = await probe.asynchronous(1)

        let expectedLine = UInt(#line + 2)
        await expectReportsIssue {
            await stub.verifyInOrder {
                _ = try await $0.asynchronousThrowing(Match.any())
            }
        } matching: { issue in
            issue.description.contains("expectation 1")
                && String(describing: issue.fileID) == String(describing: #fileID)
                && String(describing: issue.filePath) == String(describing: #filePath)
                && issue.line == expectedLine
                && issue.column > 0
        }
    }
}
