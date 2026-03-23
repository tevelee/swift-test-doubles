import XCTest
import TestDoubles

// Protocol from an "external" module — we just need ANY conformance in the binary
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

    func testZeroConfigStub() {
        // THE DREAM API: just the type parameter, nothing else
        let stub = RuntimeStub<any Calculator>()

        stub.when { $0.add(1, 2) }.returns(42)
        stub.when { $0.describe(99) }.returns("ninety-nine")
        stub.when { $0.precision }.returns(5)

        let sut = stub.proxy

        XCTAssertEqual(sut.add(1, 2), 42)
        XCTAssertEqual(sut.describe(99), "ninety-nine")
        XCTAssertEqual(sut.precision, 5)
    }

    func testZeroConfigWithMatchers() {
        let stub = RuntimeStub<any Calculator>()

        stub.when { $0.add(stub.any(), stub.any()) }.returns(100)
        stub.when { $0.describe(stub.any()) }.returns("anything")
        stub.when { $0.precision }.returns(1)

        let sut = stub.proxy
        XCTAssertEqual(sut.add(5, 10), 100)
        XCTAssertEqual(sut.add(0, 0), 100)
        XCTAssertEqual(sut.describe(42), "anything")
    }

    func testZeroConfigVerification() {
        let stub = RuntimeStub<any Calculator>()

        stub.when { $0.add(1, 2) }.returns(99)
        stub.when { $0.precision }.returns(3)

        let sut = stub.proxy
        _ = sut.add(1, 2)
        _ = sut.add(1, 2)
        _ = sut.precision

        stub.verify { $0.add(1, 2) }.wasCalled(times: 2)
        stub.verify { $0.precision }.wasCalled()
        stub.verify { $0.describe(1) }.wasNotCalled()
    }
}
