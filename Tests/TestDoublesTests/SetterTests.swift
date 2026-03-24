import XCTest
import TestDoubles

protocol Configurable {
    var name: String { get set }
    var count: Int { get }
    func reset()
}

struct RealConfigurable: Configurable {
    var name: String = ""
    var count: Int { 0 }
    func reset() {}
}

final class SetterTests: XCTestCase {

    func testGetterSetterAndVoidMethod() {
        let stub = RuntimeStub<any Configurable>()

        // Getters
        stub.when { $0.name }.returns("MockName")
        stub.when { $0.count }.returns(42)

        // #1: setter — unified `when` with inout
        stub.when { $0.name = "test" }

        // #3: void methods — no .performs() needed
        stub.when { $0.reset() }

        // #4: use stub directly
        let sut: any Configurable = stub()
        XCTAssertEqual(sut.name, "MockName")
        XCTAssertEqual(sut.count, 42)

        // Test setter
        var mutable: any Configurable = stub()
        mutable.name = "test"

        // Test void method
        sut.reset()

        // Verify — #1: unified verify for setters too
        stub.verify(called: 1) { $0.count }
        stub.verify { $0.name = "test" }.wasCalled()
        stub.verify { $0.reset() }.wasCalled()
    }
}
