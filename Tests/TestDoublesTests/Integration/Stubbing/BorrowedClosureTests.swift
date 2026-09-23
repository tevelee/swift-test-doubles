import Testing
import TestDoubles

private protocol Transformer {
    func map(_ values: [Int], transform: (Int) -> Int) -> [Int]
    func tryMap(_ values: [Int], transform: (Int) throws -> Int) rethrows -> [Int]
    func visit(_ body: (inout Int) -> Void) -> Int
}

private struct TransformerStubConformer: Transformer, ManualStubConformer {
    let stub: CompiledStub<Self>

    func map(_ values: [Int], transform: (Int) -> Int) -> [Int] {
        withoutActuallyEscaping(transform) { transform in
            let transformBorrow = BorrowedClosure(transform, parameter: "transform")
            defer { transformBorrow.end() }
            return stub.call(values, { (p0: Int) -> Int in transformBorrow { $0(p0) } })
        }
    }

    func tryMap(_ values: [Int], transform: (Int) throws -> Int) rethrows -> [Int] {
        try withoutActuallyEscaping(transform) { transform in
            let transformBorrow = BorrowedClosure(transform, parameter: "transform")
            defer { transformBorrow.end() }
            return try stub.rethrowingCall(borrowing: transformBorrow) {
                try stub.throwingCall(
                    values,
                    { (p0: Int) throws -> Int in try transformBorrow { try $0(p0) } }
                )
            }
        }
    }

    func visit(_ body: (inout Int) -> Void) -> Int {
        withoutActuallyEscaping(body) { body in
            let bodyBorrow = BorrowedClosure(body, parameter: "body")
            defer { bodyBorrow.end() }
            return stub.call({ (p0: inout Int) -> Void in bodyBorrow { $0(&p0) } })
        }
    }
}

private struct TransformFailure: Error, Equatable {}

/// Nonescaping closure arguments are lent to the stub for one call, so a
/// handler can call them while the recorded argument never outlives the call.
@Suite struct BorrowedClosureTests {
    @Test func handlersCallNonescapingClosuresDuringTheCall() {
        let stub = CompiledStub<TransformerStubConformer>()
        let maps = stub.when { $0.map(Match.any(), transform: Match.any()) }
        maps.then { (values: [Int], transform: @escaping (Int) -> Int) in values.map(transform) }

        #expect(stub().map([1, 2]) { $0 * 10 } == [10, 20])
        maps.verify()
    }

    @Test func inoutClosureParametersForwardMutations() {
        let stub = CompiledStub<TransformerStubConformer>()
        stub.when { $0.visit(Match.any()) }
            .then { (body: @escaping (inout Int) -> Void) -> Int in
                var value = 1
                body(&value)
                return value
            }

        #expect(stub().visit { $0 += 41 } == 42)
    }

    @Test func rethrowingRequirementsPropagateTheClosureError() {
        let stub = CompiledStub<TransformerStubConformer>()
        stub.when { $0.tryMap(Match.any(), transform: Match.any()) }
            .then { (values: [Int], transform: @escaping (Int) throws -> Int) in
                try values.map(transform)
            }

        #expect(throws: TransformFailure()) {
            try stub().tryMap([1]) { _ in throw TransformFailure() }
        }
        #expect(stub().tryMap([1, 2]) { $0 + 1 } == [2, 3])
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct BorrowedClosureExitTests {
        @Test func callingABorrowedClosureAfterItsCallReturnsTerminates() async {
            await #expect(processExitsWith: .failure) {
                let stub = CompiledStub<TransformerStubConformer>()
                let maps = stub.when { $0.map(Match.any(), transform: Match.any()) }
                maps.thenReturn([])
                _ = stub().map([1]) { $0 }
                let recorded: [([Int], (Int) -> Int)] = maps.arguments()
                _ = recorded[0].1(1)
            }
        }

        @Test func rethrowingRequirementsRejectErrorsTheClosureDidNotThrow() async {
            await #expect(processExitsWith: .failure) {
                let stub = CompiledStub<TransformerStubConformer>()
                stub.when { $0.tryMap(Match.any(), transform: Match.any()) }
                    .thenThrow(TransformFailure())
                _ = stub().tryMap([1]) { $0 }
            }
        }
    }
#endif
