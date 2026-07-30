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

    @Test func arraySelfArgumentsRecordWithoutRetainingElements() throws {
        _ = RealExternalArraySelfArgumentProbe()
        typealias Probe = any ExternalArraySelfArgumentProbe
        let stub = try Stub<Probe>()
        stub.when { captureArraySelf($0) }.thenDoNothing()

        let receiver: Probe = stub()
        let weakSources = try recordArraySelfStates(receiver: receiver)

        #expect(weakSources.allSatisfy { $0.value == nil })
        stub.verify(.exactly(2)) { captureArraySelf($0) }
        let method = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(method.argumentConventions == [.arraySelf])
    }

    @Test func optionalArraySelfRecordsNilEmptyAndWeakElements() throws {
        _ = RealExternalOptionalArraySelfArgumentProbe()
        typealias Probe = any ExternalOptionalArraySelfArgumentProbe
        let stub = try Stub<Probe>()
        stub.when { captureOptionalArraySelf($0) }.thenDoNothing()

        let receiver: Probe = stub()
        let weakSources = try recordOptionalArraySelfStates(
            receiver: receiver
        )

        #expect(weakSources.allSatisfy { $0.value == nil })
        stub.verify(.exactly(3)) { captureOptionalArraySelf($0) }
        let method = try #require(stub.recorder.runtimeMethod(for: 0))
        #expect(method.argumentConventions == [.optionalArraySelf])
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

private func captureArraySelf<P: ExternalArraySelfArgumentProbe>(
    _ value: P
) {
    value.accept(Match.any(using: [value]))
}

private func recordArraySelfStates<P: ExternalArraySelfArgumentProbe>(
    receiver: P
) throws -> [WeakReference<AnyObject>] {
    typealias Probe = any ExternalArraySelfArgumentProbe
    let firstStub = try Stub<Probe>()
    let secondStub = try Stub<Probe>()
    let first = try #require(firstStub() as? P)
    let second = try #require(secondStub() as? P)
    let weakSources = [
        WeakReference(first as AnyObject),
        WeakReference(second as AnyObject)
    ]
    receiver.accept([])
    receiver.accept([first, second])
    return weakSources
}

private func captureOptionalArraySelf<
    P: ExternalOptionalArraySelfArgumentProbe
>(
    _ value: P
) {
    value.accept(Match.any(using: Optional.some([value])))
}

private func recordOptionalArraySelfStates<
    P: ExternalOptionalArraySelfArgumentProbe
>(
    receiver: P
) throws -> [WeakReference<AnyObject>] {
    typealias Probe = any ExternalOptionalArraySelfArgumentProbe
    let firstStub = try Stub<Probe>()
    let secondStub = try Stub<Probe>()
    let first = try #require(firstStub() as? P)
    let second = try #require(secondStub() as? P)
    let weakSources = [
        WeakReference(first as AnyObject),
        WeakReference(second as AnyObject)
    ]
    receiver.accept(nil)
    receiver.accept([])
    receiver.accept([first, second])
    return weakSources
}
