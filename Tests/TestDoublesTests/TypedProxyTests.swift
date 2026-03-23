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

final class TypedProxyTests: XCTestCase {

    func testSlotAPI() {
        let stub = RuntimeStub<any Calculator>(
            .method(Int.self, Int.self, returns: Int.self),   // slot 0: add
            .method(Int.self, returns: String.self),           // slot 1: describe
            .getter(Int.self)                                  // slot 2: precision
        )

        stub.when { $0.add(1, 2) }.returns(42)
        stub.when { $0.describe(99) }.returns("ninety-nine")
        stub.when { $0.precision }.returns(5)

        let sut = stub.proxy
        XCTAssertEqual(sut.add(1, 2), 42)
        XCTAssertEqual(sut.describe(99), "ninety-nine")
        XCTAssertEqual(sut.precision, 5)
    }

    func testVerification() {
        let stub = RuntimeStub<any Calculator>(
            .method(Int.self, Int.self, returns: Int.self),
            .method(Int.self, returns: String.self),
            .getter(Int.self)
        )

        stub.when { $0.add(1, 2) }.returns(99)
        stub.when { $0.precision }.returns(3)

        let sut = stub.proxy
        _ = sut.add(1, 2)
        _ = sut.add(1, 2)
        _ = sut.precision

        stub.verify { $0.add(1, 2) }.wasCalled(times: 2)
        stub.verify { $0.precision }.wasCalled()
    }

    func testMatcherAny() {
        let stub = RuntimeStub<any Calculator>(
            .method(Int.self, Int.self, returns: Int.self),
            .method(Int.self, returns: String.self),
            .getter(Int.self)
        )

        stub.when { $0.add(stub.any(), stub.any()) }.returns(100)
        stub.when { $0.describe(stub.any()) }.returns("anything")
        stub.when { $0.precision }.returns(1)

        let sut = stub.proxy
        XCTAssertEqual(sut.add(5, 10), 100)
        XCTAssertEqual(sut.add(0, 0), 100)
        XCTAssertEqual(sut.describe(42), "anything")
    }

    func testVerifyNotCalled() {
        let stub = RuntimeStub<any Calculator>(
            .method(Int.self, Int.self, returns: Int.self),
            .method(Int.self, returns: String.self),
            .getter(Int.self)
        )

        stub.when { $0.add(1, 2) }.returns(0)
        stub.when { $0.precision }.returns(0)

        _ = stub.proxy.precision

        stub.verify { $0.precision }.wasCalled(times: 1)
        stub.verify { $0.add(1, 2) }.wasNotCalled()
    }
}
