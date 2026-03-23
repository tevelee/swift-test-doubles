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

    func testGetterAndSetter() {
        let stub = RuntimeStub<any Configurable>()

        // Getters
        stub.when { $0.name }.returns("MockName")
        stub.when { $0.count }.returns(42)

        // Setter — uses whenSetting for mutable access
        stub.whenSetting { $0.name = "test" }.performs()

        // Void method
        stub.when { $0.reset() }.performs()

        // Test getters
        let sut = stub.proxy
        XCTAssertEqual(sut.name, "MockName")
        XCTAssertEqual(sut.count, 42)

        // Test setter
        var mutableSut = stub.proxy
        mutableSut.name = "test"

        // Test void method
        sut.reset()

        // Verify
        stub.verify { $0.name }.wasCalled()
        stub.verify { $0.count }.wasCalled(times: 1)
        stub.verifySetting { $0.name = "test" }.wasCalled()
        stub.verify { $0.reset() }.wasCalled()
    }
}
