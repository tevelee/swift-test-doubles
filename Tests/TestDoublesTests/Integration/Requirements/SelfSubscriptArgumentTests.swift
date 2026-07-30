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

    @Test func staticArgumentsWorkEndToEnd() throws {
        _ = RealExternalStaticSelfSubscriptArgumentProbe()
        let stub = try Stub<any ExternalStaticSelfSubscriptArgumentProbe>()
        stub.when { captureStaticSelfSubscriptGet($0) }.thenReturn(46)
        stub.when { captureStaticSelfSubscriptSet($0) }.thenDoNothing()
        stub.when { captureStaticOptionalSelfSubscriptGet($0) }.thenReturn(48)
        stub.when { captureStaticOptionalSelfSubscriptSet($0) }.thenDoNothing()

        let source = stub()
        #expect(invokeStaticSelfSubscriptGet(source) == 46)
        invokeStaticSelfSubscriptSet(source)
        #expect(
            invokeStaticOptionalSelfSubscriptGet(
                source,
                includesValue: true
            ) == 48
        )
        #expect(
            invokeStaticOptionalSelfSubscriptGet(
                source,
                includesValue: false
            ) == 48
        )
        invokeStaticOptionalSelfSubscriptSet(source, includesValue: true)
        invokeStaticOptionalSelfSubscriptSet(source, includesValue: false)

        stub.verify { captureStaticSelfSubscriptGet($0) }
        stub.verify { captureStaticSelfSubscriptSet($0) }
        stub.verify(.exactly(2)) { captureStaticOptionalSelfSubscriptGet($0) }
        stub.verify(.exactly(2)) { captureStaticOptionalSelfSubscriptSet($0) }
    }

    @Test func staticThrowingArgumentsWorkEndToEnd() throws {
        _ = RealExternalStaticThrowingSelfSubscriptArgumentProbe()
        typealias Probe = any ExternalStaticThrowingSelfSubscriptArgumentProbe
        let stub = try Stub<Probe>(
            getterEffects: .throwing,
            .throwing,
            .typedThrowing(ExternalStaticSelfArgumentError.self)
        )
        stub.when {
            try captureStaticThrowingSelfSubscriptGet($0)
        }.thenReturn(54)
        stub.when {
            try captureStaticThrowingOptionalSelfSubscriptGet($0)
        }.thenThrow(ExternalStaticSelfArgumentError.rejected)
        stub.when {
            try captureStaticTypedThrowingSelfSubscriptGet($0)
        }.thenThrow(ExternalStaticSelfArgumentError.rejected)

        let source: Probe = stub()
        #expect(try invokeStaticThrowingSelfSubscriptGet(source) == 54)
        #expect(throws: ExternalStaticSelfArgumentError.rejected) {
            _ = try invokeStaticThrowingOptionalSelfSubscriptGet(
                source,
                includesValue: true
            )
        }
        #expect(throws: ExternalStaticSelfArgumentError.rejected) {
            _ = try invokeStaticThrowingOptionalSelfSubscriptGet(
                source,
                includesValue: false
            )
        }
        #expect(throws: ExternalStaticSelfArgumentError.rejected) {
            _ = try invokeStaticTypedThrowingSelfSubscriptGet(source)
        }

        stub.verify { try captureStaticThrowingSelfSubscriptGet($0) }
        stub.verify(.exactly(2)) {
            try captureStaticThrowingOptionalSelfSubscriptGet($0)
        }
        stub.verify { try captureStaticTypedThrowingSelfSubscriptGet($0) }

        let typedGetter = try #require(stub.recorder.runtimeMethod(for: 2))
        #expect(
            typedGetter.typedErrorType
                == ExternalStaticSelfArgumentError.self
        )
    }

    @Test func classConstrainedArgumentsWorkEndToEnd() throws {
        _ = RealExternalClassSelfSubscriptArgumentProbe()
        let stub = try Stub<any ExternalClassSelfSubscriptArgumentProbe>()
        stub.when { captureClassSelfSubscriptGet($0) }.thenReturn(50)
        stub.when { captureClassSelfSubscriptSet($0) }.thenDoNothing()
        stub.when { captureClassOptionalSelfSubscriptGet($0) }.thenReturn(52)
        stub.when { captureClassOptionalSelfSubscriptSet($0) }.thenDoNothing()

        let source = stub()
        #expect(invokeClassSelfSubscriptGet(source) == 50)
        invokeClassSelfSubscriptSet(source)
        #expect(
            invokeClassOptionalSelfSubscriptGet(
                source,
                includesValue: true
            ) == 52
        )
        #expect(
            invokeClassOptionalSelfSubscriptGet(
                source,
                includesValue: false
            ) == 52
        )
        invokeClassOptionalSelfSubscriptSet(source, includesValue: true)
        invokeClassOptionalSelfSubscriptSet(source, includesValue: false)

        stub.verify { captureClassSelfSubscriptGet($0) }
        stub.verify { captureClassSelfSubscriptSet($0) }
        stub.verify(.exactly(2)) { captureClassOptionalSelfSubscriptGet($0) }
        stub.verify(.exactly(2)) { captureClassOptionalSelfSubscriptSet($0) }
    }

    @Test func throwingArgumentsWorkEndToEnd() throws {
        _ = RealExternalThrowingSelfSubscriptArgumentProbe()
        let stub = try Stub<any ExternalThrowingSelfSubscriptArgumentProbe>(
            getterEffects: .throwing,
            .throwing,
            .typedThrowing(ExternalThrowingSelfArgumentError.self)
        )
        stub.when { try captureThrowingSelfSubscriptGet($0) }.thenReturn(54)
        stub.when {
            try captureThrowingOptionalSelfSubscriptGet($0)
        }.thenThrow(ExternalThrowingSelfArgumentError.rejected)
        stub.when {
            try captureTypedThrowingSelfSubscriptGet($0)
        }.thenThrow(ExternalThrowingSelfArgumentError.rejected)

        let source = stub()
        #expect(try invokeThrowingSelfSubscriptGet(source) == 54)
        #expect(throws: ExternalThrowingSelfArgumentError.rejected) {
            _ = try invokeThrowingOptionalSelfSubscriptGet(
                source,
                includesValue: true
            )
        }
        #expect(throws: ExternalThrowingSelfArgumentError.rejected) {
            _ = try invokeThrowingOptionalSelfSubscriptGet(
                source,
                includesValue: false
            )
        }
        #expect(throws: ExternalThrowingSelfArgumentError.rejected) {
            _ = try invokeTypedThrowingSelfSubscriptGet(source)
        }

        stub.verify { try captureThrowingSelfSubscriptGet($0) }
        stub.verify(.exactly(2)) {
            try captureThrowingOptionalSelfSubscriptGet($0)
        }
        stub.verify { try captureTypedThrowingSelfSubscriptGet($0) }

        let typedGetter = try #require(stub.recorder.runtimeMethod(for: 2))
        #expect(
            typedGetter.typedErrorType
                == ExternalThrowingSelfArgumentError.self
        )
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

private func captureClassSelfSubscriptGet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    value[Match.any(using: value)]
}

private func captureClassSelfSubscriptSet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    let receiver = value
    receiver[Match.any(using: value)] = Match.equal(51)
}

private func captureClassOptionalSelfSubscriptGet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    value[optional: Match.any(using: Optional(value))]
}

private func captureClassOptionalSelfSubscriptSet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    let receiver = value
    receiver[optional: Match.any(using: Optional(value))] = Match.equal(53)
}

private func invokeClassSelfSubscriptGet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    value[value]
}

private func invokeClassSelfSubscriptSet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    let receiver = value
    receiver[value] = 51
}

private func invokeClassOptionalSelfSubscriptGet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) -> Int {
    value[optional: includesValue ? value : nil]
}

private func invokeClassOptionalSelfSubscriptSet<
    P: ExternalClassSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) {
    let receiver = value
    receiver[optional: includesValue ? value : nil] = 53
}

private func captureThrowingSelfSubscriptGet<
    P: ExternalThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws -> Int {
    try value[Match.any(using: value)]
}

private func captureThrowingOptionalSelfSubscriptGet<
    P: ExternalThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws -> Int {
    try value[optional: Match.any(using: Optional(value))]
}

private func invokeThrowingSelfSubscriptGet<
    P: ExternalThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws -> Int {
    try value[value]
}

private func invokeThrowingOptionalSelfSubscriptGet<
    P: ExternalThrowingSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) throws -> Int {
    try value[optional: includesValue ? value : nil]
}

private func captureTypedThrowingSelfSubscriptGet<
    P: ExternalThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) -> Int {
    try value[typed: Match.any(using: value)]
}

private func invokeTypedThrowingSelfSubscriptGet<
    P: ExternalThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws(ExternalThrowingSelfArgumentError) -> Int {
    try value[typed: value]
}

private func captureStaticSelfSubscriptGet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    type(of: value)[Match.any(using: value)]
}

private func captureStaticSelfSubscriptSet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    type(of: value)[Match.any(using: value)] = Match.equal(47)
}

private func captureStaticOptionalSelfSubscriptGet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    type(of: value)[optional: Match.any(using: Optional(value))]
}

private func captureStaticOptionalSelfSubscriptSet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    type(of: value)[optional: Match.any(using: Optional(value))] =
        Match.equal(49)
}

private func invokeStaticSelfSubscriptGet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P
) -> Int {
    type(of: value)[value]
}

private func invokeStaticSelfSubscriptSet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P
) {
    type(of: value)[value] = 47
}

private func invokeStaticOptionalSelfSubscriptGet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) -> Int {
    type(of: value)[optional: includesValue ? value : nil]
}

private func invokeStaticOptionalSelfSubscriptSet<
    P: ExternalStaticSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) {
    type(of: value)[optional: includesValue ? value : nil] = 49
}

private func captureStaticThrowingSelfSubscriptGet<
    P: ExternalStaticThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws -> Int {
    try type(of: value)[Match.any(using: value)]
}

private func captureStaticThrowingOptionalSelfSubscriptGet<
    P: ExternalStaticThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws -> Int {
    try type(of: value)[optional: Match.any(using: Optional(value))]
}

private func captureStaticTypedThrowingSelfSubscriptGet<
    P: ExternalStaticThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws(ExternalStaticSelfArgumentError) -> Int {
    try type(of: value)[typed: Match.any(using: value)]
}

private func invokeStaticThrowingSelfSubscriptGet<
    P: ExternalStaticThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws -> Int {
    try type(of: value)[value]
}

private func invokeStaticThrowingOptionalSelfSubscriptGet<
    P: ExternalStaticThrowingSelfSubscriptArgumentProbe
>(
    _ value: P,
    includesValue: Bool
) throws -> Int {
    try type(of: value)[optional: includesValue ? value : nil]
}

private func invokeStaticTypedThrowingSelfSubscriptGet<
    P: ExternalStaticThrowingSelfSubscriptArgumentProbe
>(
    _ value: P
) throws(ExternalStaticSelfArgumentError) -> Int {
    try type(of: value)[typed: value]
}
