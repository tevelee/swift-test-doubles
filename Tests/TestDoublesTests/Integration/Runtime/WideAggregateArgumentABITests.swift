import Testing
import TestDoublesRuntimeMetadata
@testable import TestDoubles

/// Four words, the widest explosion Swift still passes in registers.
struct WidestDirectABIArgument: Equatable, Sendable {
    let label: String
    let detail: String
}

/// Three words mixing a scalar with reference-counted storage.
struct MixedWideABIArgument: Equatable, Sendable {
    let id: Int
    let label: String
}

/// Six sub-word fields, which Swift packs into three registers rather than six.
struct PackedInt32ABIArgument: Equatable, Sendable {
    let a: Int32
    let b: Int32
    let c: Int32
    let d: Int32
    let e: Int32
    let f: Int32
}

/// Five words, one past the register limit, so the caller passes an address.
struct SpilledABIArgument: Equatable, Sendable {
    let first: Int
    let second: Int
    let third: Int
    let fourth: Int
    let fifth: Int
}

protocol WideArgumentABIProbe {
    func take(_ value: OrdinaryWideABIValue) -> Int
    func takeWidest(_ value: WidestDirectABIArgument) -> String
    func takeMixed(id: Int, value: MixedWideABIArgument) -> String
    func takeSpilled(_ value: SpilledABIArgument) -> Int
    func takePacked(_ value: PackedInt32ABIArgument) -> Int32
}

struct RealWideArgumentABIProbe: WideArgumentABIProbe {
    func take(_ value: OrdinaryWideABIValue) -> Int { 0 }
    func takeWidest(_ value: WidestDirectABIArgument) -> String { "" }
    func takeMixed(id: Int, value: MixedWideABIArgument) -> String { "" }
    func takeSpilled(_ value: SpilledABIArgument) -> Int { 0 }
    func takePacked(_ value: PackedInt32ABIArgument) -> Int32 { 0 }
}

/// A loadable aggregate wider than two words is exploded into registers when it
/// is passed, exactly as when it is returned, until the explosion outgrows the
/// register limit.
@Suite struct WideAggregateArgumentABITests {
    @Test func wideAggregateArgumentsClassifyAsRegisterParts() {
        guard case .aggregate(let parts) = abiClass(for: OrdinaryWideABIValue.self) else {
            Issue.record("A three-word loadable aggregate argument is passed in registers.")
            return
        }
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.register == .gp })
    }

    @Test func aggregateArgumentsBeyondTheRegisterLimitStayIndirect() {
        guard case .indirect = abiClass(for: SpilledABIArgument.self) else {
            Issue.record("A five-word aggregate argument no longer fits in registers.")
            return
        }
    }

    @Test func wideIntegerAggregateArgument() throws {
        let stub = try Stub<any WideArgumentABIProbe>()
        stub.when { $0.take(Match.any()) }.then { (value: OrdinaryWideABIValue) in
            value.first + value.second + value.third
        }

        let value = OrdinaryWideABIValue(first: 1, second: 2, third: 3)
        #expect(stub().take(value) == 6)
        stub.verify { $0.take(Match.equal(value)) }
    }

    @Test func widestDirectAggregateArgument() throws {
        let stub = try Stub<any WideArgumentABIProbe>()
        stub.when { $0.takeWidest(Match.any()) }.then { (value: WidestDirectABIArgument) in
            "\(value.label)/\(value.detail)"
        }

        let value = WidestDirectABIArgument(label: "a", detail: "b")
        #expect(stub().takeWidest(value) == "a/b")
        stub.verify { $0.takeWidest(Match.equal(value)) }
    }

    @Test func wideAggregateArgumentAfterAScalar() throws {
        let stub = try Stub<any WideArgumentABIProbe>()
        stub.when { $0.takeMixed(id: Match.any(), value: Match.any()) }
            .then { (id: Int, value: MixedWideABIArgument) in "\(id):\(value.id):\(value.label)" }

        let value = MixedWideABIArgument(id: 7, label: "x")
        #expect(stub().takeMixed(id: 3, value: value) == "3:7:x")
        stub.verify { $0.takeMixed(id: Match.equal(3), value: Match.equal(value)) }
    }

    @Test func subWordFieldsShareWholeRegisters() {
        guard case .aggregate(let parts) = abiClass(for: PackedInt32ABIArgument.self) else {
            Issue.record("Six packed Int32 fields occupy three registers, not six.")
            return
        }
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.register == .gp })
    }

    @Test func packedSubWordAggregateArgument() throws {
        let stub = try Stub<any WideArgumentABIProbe>()
        stub.when { $0.takePacked(Match.any()) }.then { (value: PackedInt32ABIArgument) in
            value.a + value.f
        }

        let value = PackedInt32ABIArgument(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6)
        let result = stub().takePacked(value)
        #expect(result == 7)
        stub.verify { $0.takePacked(Match.equal(value)) }
    }

    @Test func aggregateArgumentPastTheRegisterLimit() throws {
        let stub = try Stub<any WideArgumentABIProbe>()
        stub.when { $0.takeSpilled(Match.any()) }.then { (value: SpilledABIArgument) in
            value.first + value.fifth
        }

        let value = SpilledABIArgument(first: 1, second: 2, third: 3, fourth: 4, fifth: 5)
        #expect(stub().takeSpilled(value) == 6)
        stub.verify { $0.takeSpilled(Match.equal(value)) }
    }
}
