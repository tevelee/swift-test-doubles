import Testing
@testable import TestDoubles

private protocol NoncopyableProtocolBoundaryProbe: ~Copyable {
    func value() -> Int
}

private protocol NonescapableProtocolBoundaryProbe: ~Escapable {
    func value() -> Int
}

@Suite struct DeferredProtocolBoundaryTests {
    @Test func noncopyableProtocolsFailWithTheirRecorderBoundary() {
        expectUnsupportedProtocolShape(containing: "requires Copyable payloads") {
            _ = try Stub<any NoncopyableProtocolBoundaryProbe>(
                .method(returning: Int.self)
            )
        }
    }

    @Test func nonescapableProtocolsFailWithTheirRecorderBoundary() {
        expectUnsupportedProtocolShape(containing: "requires Escapable payloads") {
            _ = try Stub<any NonescapableProtocolBoundaryProbe>(
                .method(returning: Int.self)
            )
        }
    }
}
