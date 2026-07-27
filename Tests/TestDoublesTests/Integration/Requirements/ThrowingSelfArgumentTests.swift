import TestDoublesFixtures
import Testing
@testable import TestDoubles

@Suite struct ThrowingSelfArgumentTests {
    @Test func argumentsRecordStubAndVerifySuccess() throws {
        _ = RealExternalThrowingSelfArgumentProbe()

        let stub = try Stub<any ExternalThrowingSelfArgumentProbe>()
        configureSuccessfulThrowingSelfArgumentStub(stub)

        let source = stub()
        try exerciseSuccessfulThrowingSelfArguments(source)

        verifySuccessfulThrowingSelfArgumentCalls(stub)
    }

    @Test func argumentsPropagateUntypedAndTypedErrors() throws {
        _ = RealExternalThrowingSelfArgumentProbe()
        let stub = try Stub<any ExternalThrowingSelfArgumentProbe>()
        configureFailingThrowingSelfArgumentStub(stub)

        let source = stub()
        exerciseFailingThrowingSelfArguments(source)

        verifyFailingThrowingSelfArgumentCalls(stub)
    }

    @Test func consumingClassArgumentReleasesOnErrorPath() throws {
        let weakReference = try exerciseConsumingThrowingClassLifetime()

        #expect(weakReference.value == nil)
    }
}

private func configureSuccessfulThrowingSelfArgumentStub(
    _ stub: Stub<any ExternalThrowingSelfArgumentProbe>
) {
    stub.when { try captureThrowingAccept($0) }.thenDoNothing()
    stub.when { try captureThrowingBorrow($0) }.thenDoNothing()
    stub.when { try captureThrowingConsume($0) }.thenDoNothing()
    stub.when { try captureThrowingOptional($0) }.thenDoNothing()
    stub.when { try captureThrowingConsumingOptional($0) }.thenDoNothing()
    stub.when { try captureTypedThrowingAccept($0) }.thenDoNothing()
    stub.when { try captureTypedThrowingConsume($0) }.thenDoNothing()
    stub.when { try captureTypedThrowingOptional($0) }.thenDoNothing()
    stub.when { try captureTypedThrowingConsumingOptional($0) }.thenDoNothing()
}

private func exerciseSuccessfulThrowingSelfArguments<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws {
    try invokeThrowingAccept(value)
    try invokeThrowingBorrow(value)
    try invokeThrowingConsume(value)
    try invokeThrowingOptional(value, includesValue: true)
    try invokeThrowingOptional(value, includesValue: false)
    try invokeThrowingConsumingOptional(value, includesValue: true)
    try invokeThrowingConsumingOptional(value, includesValue: false)
    try invokeTypedThrowingAccept(value)
    try invokeTypedThrowingConsume(value)
    try invokeTypedThrowingOptional(value, includesValue: true)
    try invokeTypedThrowingOptional(value, includesValue: false)
    try invokeTypedThrowingConsumingOptional(value, includesValue: true)
    try invokeTypedThrowingConsumingOptional(value, includesValue: false)
}

private func verifySuccessfulThrowingSelfArgumentCalls(
    _ stub: Stub<any ExternalThrowingSelfArgumentProbe>
) {
    stub.verify { try captureThrowingAccept($0) }
    stub.verify { try captureThrowingBorrow($0) }
    stub.verify { try captureThrowingConsume($0) }
    stub.verify(.exactly(2)) { try captureThrowingOptional($0) }
    stub.verify(.exactly(2)) { try captureThrowingConsumingOptional($0) }
    stub.verify { try captureTypedThrowingAccept($0) }
    stub.verify { try captureTypedThrowingConsume($0) }
    stub.verify(.exactly(2)) { try captureTypedThrowingOptional($0) }
    stub.verify(.exactly(2)) {
        try captureTypedThrowingConsumingOptional($0)
    }
}

private func configureFailingThrowingSelfArgumentStub(
    _ stub: Stub<any ExternalThrowingSelfArgumentProbe>
) {
    let error = ExternalThrowingSelfArgumentError.rejected
    stub.when { try captureThrowingAccept($0) }.thenThrow(error)
    stub.when { try captureThrowingBorrow($0) }.thenThrow(error)
    stub.when { try captureThrowingConsume($0) }.thenThrow(error)
    stub.when { try captureThrowingOptional($0) }.thenThrow(error)
    stub.when { try captureThrowingConsumingOptional($0) }.thenThrow(error)
    stub.when { try captureTypedThrowingAccept($0) }.thenThrow(error)
    stub.when { try captureTypedThrowingConsume($0) }.thenThrow(error)
    stub.when { try captureTypedThrowingOptional($0) }.thenThrow(error)
    stub.when { try captureTypedThrowingConsumingOptional($0) }
        .thenThrow(error)
}

private func exerciseFailingThrowingSelfArguments<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) {
    let expected = ExternalThrowingSelfArgumentError.rejected
    #expect(throws: expected) { try invokeThrowingAccept(value) }
    #expect(throws: expected) { try invokeThrowingBorrow(value) }
    #expect(throws: expected) { try invokeThrowingConsume(value) }
    #expect(throws: expected) {
        try invokeThrowingOptional(value, includesValue: true)
    }
    #expect(throws: expected) {
        try invokeThrowingConsumingOptional(value, includesValue: true)
    }
    #expect(throws: expected) { try invokeTypedThrowingAccept(value) }
    #expect(throws: expected) { try invokeTypedThrowingConsume(value) }
    #expect(throws: expected) {
        try invokeTypedThrowingOptional(value, includesValue: true)
    }
    #expect(throws: expected) {
        try invokeTypedThrowingConsumingOptional(value, includesValue: true)
    }
}

private func verifyFailingThrowingSelfArgumentCalls(
    _ stub: Stub<any ExternalThrowingSelfArgumentProbe>
) {
    stub.verify { try captureThrowingAccept($0) }
    stub.verify { try captureThrowingBorrow($0) }
    stub.verify { try captureThrowingConsume($0) }
    stub.verify { try captureThrowingOptional($0) }
    stub.verify { try captureThrowingConsumingOptional($0) }
    stub.verify { try captureTypedThrowingAccept($0) }
    stub.verify { try captureTypedThrowingConsume($0) }
    stub.verify { try captureTypedThrowingOptional($0) }
    stub.verify { try captureTypedThrowingConsumingOptional($0) }
}

private func captureThrowingAccept<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.accept(any(using: value))
}

private func captureThrowingBorrow<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.borrow(any(using: value))
}

private func captureThrowingConsume<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.consume(any(using: value))
}

private func captureThrowingOptional<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.acceptOptional(any(using: Optional(value)))
}

private func captureThrowingConsumingOptional<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws {
    try value.consumeOptional(any(using: Optional(value)))
}

private func captureTypedThrowingAccept<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) {
    try value.acceptTyped(any(using: value))
}

private func captureTypedThrowingConsume<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) {
    try value.consumeTyped(any(using: value))
}

private func captureTypedThrowingOptional<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) {
    try value.acceptOptionalTyped(any(using: Optional(value)))
}

private func captureTypedThrowingConsumingOptional<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) {
    try value.consumeOptionalTyped(any(using: Optional(value)))
}

private func invokeThrowingAccept<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.accept(value)
}

private func invokeThrowingBorrow<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.borrow(value)
}

private func invokeThrowingConsume<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P
) throws {
    try value.consume(value)
}

private func invokeThrowingOptional<P: ExternalThrowingSelfArgumentProbe>(
    _ value: P,
    includesValue: Bool
) throws {
    try value.acceptOptional(includesValue ? value : nil)
}

private func invokeThrowingConsumingOptional<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) throws {
    try value.consumeOptional(includesValue ? value : nil)
}

private func invokeTypedThrowingAccept<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) {
    try value.acceptTyped(value)
}

private func invokeTypedThrowingConsume<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) {
    try value.consumeTyped(value)
}

private func invokeTypedThrowingOptional<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) throws(ExternalThrowingSelfArgumentError) {
    try value.acceptOptionalTyped(includesValue ? value : nil)
}

private func invokeTypedThrowingConsumingOptional<
    P: ExternalThrowingSelfArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) throws(ExternalThrowingSelfArgumentError) {
    try value.consumeOptionalTyped(includesValue ? value : nil)
}

private func exerciseConsumingThrowingClassLifetime() throws
    -> WeakReference<AnyObject>
{
    _ = RealExternalThrowingClassSelfArgumentProbe()
    let stub = try Stub<any ExternalThrowingClassSelfArgumentProbe>()
    stub.when { try captureThrowingClassConsume($0) }
        .thenThrow(ExternalThrowingSelfArgumentError.rejected)

    let receiver = stub()
    var source: (any ExternalThrowingClassSelfArgumentProbe)? = stub()
    let weakReference = WeakReference(try #require(source) as AnyObject)
    do {
        let source = try #require(source)
        #expect(throws: ExternalThrowingSelfArgumentError.rejected) {
            try invokeThrowingClassConsume(
                receiver,
                source: consume source
            )
        }
    }
    source = nil
    stub.verify { try captureThrowingClassConsume($0) }
    return weakReference
}

private func captureThrowingClassConsume<
    P: ExternalThrowingClassSelfArgumentProbe
>(
    _ value: P
) throws {
    try value.consume(any(using: value))
}

private func invokeThrowingClassConsume<
    P: ExternalThrowingClassSelfArgumentProbe
>(
    _ receiver: P,
    source: consuming any ExternalThrowingClassSelfArgumentProbe
) throws {
    let source = try #require(source as? P)
    try receiver.consume(consume source)
}
