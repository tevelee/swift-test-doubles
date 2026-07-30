import InternalRuntimeContract
import TestDoublesFixtures
import Testing
@testable import TestDoubles

@Suite struct NestedSelfArgumentTests {
    @Test func nestedOptionalSelfArgumentsRecordAllNilStates() throws {
        _ = RealExternalNestedOptionalSelfArgumentProbe()
        typealias Probe = any ExternalNestedOptionalSelfArgumentProbe
        let stub = try Stub<Probe>()
        stub.when { captureNestedOptionalSelf($0) }.thenDoNothing()

        let receiver: Probe = stub()
        let weakSource = try recordNestedOptionalSelfStates(receiver: receiver)

        #expect(weakSource.value == nil)
        stub.verify(.exactly(3)) { captureNestedOptionalSelf($0) }
        let method = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(method.argumentConventions == [.nestedOptionalSelf])
    }
}

private func captureNestedOptionalSelf<
    P: ExternalNestedOptionalSelfArgumentProbe
>(
    _ value: P
) {
    let placeholder: P?? = .some(.some(value))
    value.accept(Match.any(using: placeholder))
}

private func recordNestedOptionalSelfStates<
    P: ExternalNestedOptionalSelfArgumentProbe
>(
    receiver: P
) throws -> WeakReference<AnyObject> {
    typealias Probe = any ExternalNestedOptionalSelfArgumentProbe
    let sourceStub = try Stub<Probe>()
    let source = try #require(sourceStub() as? P)
    let weakSource = WeakReference(source as AnyObject)
    receiver.accept(nil)
    receiver.accept(.some(nil))
    receiver.accept(.some(.some(source)))
    return weakSource
}
