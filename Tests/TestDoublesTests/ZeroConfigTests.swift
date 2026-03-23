import XCTest
import TestDoubles

protocol Calculator {
    func add(_ a: Int, _ b: Int) -> Int
    func describe(_ value: Int) -> String
    var precision: Int { get }
}

struct RealCalculator: Calculator {
    func add(_ a: Int, _ b: Int) -> Int { a + b }
    func describe(_ value: Int) -> String { "\(value)" }
    var precision: Int { 10 }
}

final class ZeroConfigTests: XCTestCase {

    func testZeroConfig() {
        let stub = RuntimeStub<any Calculator>()

        stub.when { $0.add(1, 2) }.returns(42)
        stub.when { $0.describe(99) }.returns("ninety-nine")
        stub.when { $0.precision }.returns(5)

        // #4: stub() as protocol directly
        let sut: any Calculator = stub()

        XCTAssertEqual(sut.add(1, 2), 42)
        XCTAssertEqual(sut.describe(99), "ninety-nine")
        XCTAssertEqual(sut.precision, 5)
    }

    func testFreeMatchers() {
        let stub = RuntimeStub<any Calculator>()

        // #2: free-function matchers — no stub. prefix needed
        stub.when { $0.add(any(), any()) }.returns(100)
        stub.when { $0.describe(any()) }.returns("anything")
        stub.when { $0.precision }.returns(1)

        let sut: any Calculator = stub()
        XCTAssertEqual(sut.add(5, 10), 100)
        XCTAssertEqual(sut.add(0, 0), 100)
        XCTAssertEqual(sut.describe(42), "anything")
    }

    func testConciseVerify() {
        let stub = RuntimeStub<any Calculator>()

        stub.when { $0.add(1, 2) }.returns(99)
        stub.when { $0.precision }.returns(3)

        let sut: any Calculator = stub()
        _ = sut.add(1, 2)
        _ = sut.add(1, 2)
        _ = sut.precision

        // #5: concise verify
        stub.verify(called: 2) { $0.add(1, 2) }
        stub.verify(called: 1) { $0.precision }
        stub.verify(never: { $0.describe(1) })
    }

    func testBuilderVerify() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.add(any(), any()) }.returns(0)

        _ = stub().add(1, 2)

        stub.verify { $0.add(1, 2) }.wasCalled()
        stub.verify { $0.add(1, 2) }.wasCalled(times: 1)
    }
}
