import TestDoubles
import TestDoublesTesting
import XCTest

final class XCTestScopedValidationTests: XCTestCase {
    private enum ExpectedFailure: Error, Equatable {
        case stopped
    }

    func testSynchronousScopeReturnsItsResult() throws {
        let result = try TestDouble.withScope(checking: .strict) {
            let double = ClosureDouble<Int, Int>()
            let call = double.when(equal: 21).thenReturn(42)

            let result = double.function(21)
            call.verify()
            return result
        }

        XCTAssertEqual(result, 42)
    }

    func testAsynchronousScopeReturnsItsResult() async throws {
        let result = try await TestDouble.withScope(checking: .strict) {
            let double = AsyncClosureDouble<Int, Int>()
            let call = double.when(equal: 21).thenReturn(42)

            let result = await double.function(21)
            call.verify()
            return result
        }

        XCTAssertEqual(result, 42)
    }

    func testScopePreservesThrownError() {
        XCTAssertThrowsError(
            try TestDouble.withScope(checking: []) {
                throw ExpectedFailure.stopped
            }
        ) { error in
            XCTAssertEqual(error as? ExpectedFailure, .stopped)
        }
    }
}
