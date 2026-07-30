import TestDoublesFixtures
import Testing
@testable import TestDoubles

@Suite struct SelfSubscriptArgumentTests {
    @Test func argumentsWorkEndToEnd() throws {
        _ = RealExternalSelfSubscriptArgumentProbe()
        let stub = try Stub<any ExternalSelfSubscriptArgumentProbe>()
        stub.when { captureSelfSubscriptGet($0) }.thenReturn(42)
        stub.when { captureSelfSubscriptSet($0) }.thenDoNothing()
        stub.when { captureOptionalSelfSubscriptGet($0) }.thenReturn(44)
        stub.when { captureOptionalSelfSubscriptSet($0) }.thenDoNothing()

        let source = stub()
        #expect(invokeSelfSubscriptGet(source) == 42)
        invokeSelfSubscriptSet(source)
        #expect(
            invokeOptionalSelfSubscriptGet(source, includesValue: true) == 44
        )
        #expect(
            invokeOptionalSelfSubscriptGet(source, includesValue: false) == 44
        )
        invokeOptionalSelfSubscriptSet(source, includesValue: true)
        invokeOptionalSelfSubscriptSet(source, includesValue: false)

        stub.verify { captureSelfSubscriptGet($0) }
        stub.verify { captureSelfSubscriptSet($0) }
        stub.verify(.exactly(2)) { captureOptionalSelfSubscriptGet($0) }
        stub.verify(.exactly(2)) { captureOptionalSelfSubscriptSet($0) }
    }
}

private func captureSelfSubscriptGet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    value[Match.any(using: value)]
}

private func captureSelfSubscriptSet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    var receiver = value
    let index = value
    receiver[Match.any(using: index)] = Match.equal(43)
}

private func captureOptionalSelfSubscriptGet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    value[optional: Match.any(using: Optional(value))]
}

private func captureOptionalSelfSubscriptSet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    var receiver = value
    receiver[optional: Match.any(using: Optional(value))] = Match.equal(45)
}

private func invokeSelfSubscriptGet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    value[value]
}

private func invokeSelfSubscriptSet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    var receiver = value
    receiver[value] = 43
}

private func invokeOptionalSelfSubscriptGet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) -> Int {
    value[optional: includesValue ? value : nil]
}

private func invokeOptionalSelfSubscriptSet<
    P: ExternalSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) {
    var receiver = value
    receiver[optional: includesValue ? value : nil] = 45
}
