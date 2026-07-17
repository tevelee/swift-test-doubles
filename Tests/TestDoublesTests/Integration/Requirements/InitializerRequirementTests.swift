import Testing
@testable import TestDoubles

protocol InitializerRequirementProbe {
    init(value: String)
    func storedValue() -> String
}

struct RealInitializerRequirementProbe: InitializerRequirementProbe {
    init(value: String) {}
    func storedValue() -> String { "real" }
}

private protocol ExplicitInitializerRequirementProbe {
    init(value: Int)
    func storedValue() -> Int
}

protocol AssociatedTypeInitializerRequirementProbe<Element> {
    associatedtype Element

    init(value: Element)
    func storedValue() -> Element
}

struct RealAssociatedTypeInitializerRequirementProbe:
    AssociatedTypeInitializerRequirementProbe
{
    let value: Int

    func storedValue() -> Int { value }
}

private protocol ExplicitAssociatedTypeInitializerRequirementProbe<Element> {
    associatedtype Element

    init(value: Element)
    func storedValue() -> Element
}

protocol FailableInitializerRequirementProbe {
    init?(value: Int)
    func storedValue() -> Int
}

struct RealFailableInitializerRequirementProbe: FailableInitializerRequirementProbe {
    init?(value: Int) {
        if value < 0 { return nil }
    }

    func storedValue() -> Int { 0 }
}

private enum InitializerRequirementError: Error, Equatable {
    case rejected(Int)
}

protocol ThrowingInitializerRequirementProbe {
    init(value: Int) throws
    func storedValue() -> Int
}

struct RealThrowingInitializerRequirementProbe: ThrowingInitializerRequirementProbe {
    init(value: Int) throws {}
    func storedValue() -> Int { 0 }
}

protocol AsyncInitializerRequirementProbe {
    init(value: Int) async throws
    func storedValue() -> Int
}

struct RealAsyncInitializerRequirementProbe: AsyncInitializerRequirementProbe {
    init(value: Int) async throws {}
    func storedValue() -> Int { 0 }
}

protocol AsyncFailableInitializerRequirementProbe {
    init?(value: Int) async throws
    func storedValue() -> Int
}

struct RealAsyncFailableInitializerRequirementProbe: AsyncFailableInitializerRequirementProbe {
    init?(value: Int) async throws {
        if value < 0 { return nil }
    }

    func storedValue() -> Int { 0 }
}

protocol ClassInitializerRequirementProbe: AnyObject {
    init()
    init?(enabled: Bool)
}

final class RealClassInitializerRequirementProbe: ClassInitializerRequirementProbe {
    init() {}

    init?(enabled: Bool) {
        if enabled == false { return nil }
    }
}

protocol BaseInitializerRequirementProbe {
    init(baseValue: Int)
    func storedValue() -> Int
}

protocol ChildInitializerRequirementProbe: BaseInitializerRequirementProbe {
    func childValue() -> Int
}

struct RealChildInitializerRequirementProbe: ChildInitializerRequirementProbe {
    init(baseValue: Int) {}
    func storedValue() -> Int { 0 }
    func childValue() -> Int { 0 }
}

@inline(never)
private func useLinkedInitializerRequirement(
    _ value: any InitializerRequirementProbe
) -> String {
    type(of: value).init(value: "linked").storedValue()
}

@inline(never)
private func useLinkedAssociatedTypeInitializerRequirement(
    _ value: any AssociatedTypeInitializerRequirementProbe<Int>
) -> Int {
    type(of: value).init(value: 41).storedValue()
}

@inline(never)
private func useLinkedFailableInitializerRequirement(
    _ value: any FailableInitializerRequirementProbe
) -> Int? {
    type(of: value).init(value: 0)?.storedValue()
}

@inline(never)
private func useLinkedThrowingInitializerRequirement(
    _ value: any ThrowingInitializerRequirementProbe
) throws -> Int {
    try type(of: value).init(value: 0).storedValue()
}

@inline(never)
private func useLinkedAsyncInitializerRequirement(
    _ value: any AsyncInitializerRequirementProbe
) async throws -> Int {
    try await type(of: value).init(value: 0).storedValue()
}

@inline(never)
private func useLinkedClassInitializerRequirement(
    _ value: any ClassInitializerRequirementProbe
) -> any ClassInitializerRequirementProbe {
    type(of: value).init()
}

@inline(never)
private func useLinkedChildInitializerRequirement(
    _ value: any ChildInitializerRequirementProbe
) -> Int {
    type(of: value).init(baseValue: 0).childValue()
}

struct InitializerRequirementTests {
    @Test func automaticDiscoverySupportsNonfailableInitializers() throws {
        #expect(
            useLinkedInitializerRequirement(
                RealInitializerRequirementProbe(value: "linked")
            ) == "real"
        )
        let stub = try Stub<any InitializerRequirementProbe>()
        stub.when(initializer: { type(of: $0).init(value: any()) }).thenInitialize()
        stub.when { $0.storedValue() }.thenReturn("stubbed")

        let seed: any InitializerRequirementProbe = stub()
        let initialized = type(of: seed).init(value: "created")

        #expect(initialized.storedValue() == "stubbed")
        stub.verify { type(of: $0).init(value: equal("created")) }
    }

    @Test func explicitInitializersWorkWithoutAConformer() throws {
        let stub = try Stub<any ExplicitInitializerRequirementProbe>(
            .initializer(Int.self),
            .method(returning: Int.self)
        )
        stub.when(initializer: { type(of: $0).init(value: any()) }).thenInitialize()
        stub.when { $0.storedValue() }.thenReturn(42)

        let seed: any ExplicitInitializerRequirementProbe = stub()
        let initialized = type(of: seed).init(value: 7)

        #expect(initialized.storedValue() == 42)
        stub.verify { type(of: $0).init(value: equal(7)) }
    }

    @Test func automaticDiscoverySupportsAssociatedTypeInitializerArguments() throws {
        #expect(
            useLinkedAssociatedTypeInitializerRequirement(
                RealAssociatedTypeInitializerRequirementProbe(value: 0)
            ) == 41
        )
        typealias ProbeStub = Stub<any AssociatedTypeInitializerRequirementProbe<Int>>
        let stub = try ProbeStub()
        try assertAssociatedTypeInitializerDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            argumentType: Int.self
        )
        stub.when(initializer: {
            type(of: $0).init(value: any())
        }).thenInitialize()
        stub.when { $0.storedValue() }.thenReturn(42)

        let seed: any AssociatedTypeInitializerRequirementProbe<Int> = stub()
        let initialized = type(of: seed).init(value: 7)

        #expect(initialized.storedValue() == 42)
        stub.verify { type(of: $0).init(value: equal(7)) }
    }

    @Test func explicitRequirementsSupportAssociatedTypeInitializerArguments() throws {
        typealias ProbeStub = Stub<
            any ExplicitAssociatedTypeInitializerRequirementProbe<String>
        >
        let element = ProbeStub.Requirement.Value.associatedType(named: "Element")
        let stub = try ProbeStub(
            .initializer(element),
            .method(returning: element)
        )
        try assertAssociatedTypeInitializerDescriptor(
            #require(stub.recorder.runtimeMethod(for: 0)),
            argumentType: String.self
        )
        stub.when(initializer: {
            type(of: $0).init(value: any())
        }).thenInitialize()
        stub.when { $0.storedValue() }.thenReturn("stubbed")

        let seed: any ExplicitAssociatedTypeInitializerRequirementProbe<String> = stub()
        let initialized = type(of: seed).init(value: "created")

        #expect(initialized.storedValue() == "stubbed")
        stub.verify { type(of: $0).init(value: equal("created")) }
    }

    @Test func failableInitializersChooseSuccessOrNilWithMatchers() throws {
        #expect(
            useLinkedFailableInitializerRequirement(
                try #require(RealFailableInitializerRequirementProbe(value: 0))
            ) == 0
        )
        let stub = try Stub<any FailableInitializerRequirementProbe>()
        stub.when(initializer: {
            type(of: $0).init(value: equal(1))
        }).thenInitialize()
        stub.when(initializer: {
            type(of: $0).init(value: any())
        }).thenReturnNil()
        stub.when { $0.storedValue() }.thenReturn(21)

        let seed: any FailableInitializerRequirementProbe = stub()
        let success = type(of: seed).init(value: 1)
        let failure = type(of: seed).init(value: -1)

        #expect(success?.storedValue() == 21)
        #expect(failure == nil)
        stub.verify { type(of: $0).init(value: equal(1)) }
        stub.verify { type(of: $0).init(value: equal(-1)) }
    }

    @Test func throwingInitializerHandlersPropagateErrors() throws {
        #expect(
            try useLinkedThrowingInitializerRequirement(
                RealThrowingInitializerRequirementProbe(value: 0)
            ) == 0
        )
        let stub = try Stub<any ThrowingInitializerRequirementProbe>()
        stub.when(initializer: {
            try type(of: $0).init(value: any())
        }).thenInitialize()
        stub.when(initializer: {
            try type(of: $0).init(value: equal(-2))
        }).thenThrow(InitializerRequirementError.rejected(-2))
        stub.when { $0.storedValue() }.thenReturn(34)

        let seed: any ThrowingInitializerRequirementProbe = stub()
        #expect(try type(of: seed).init(value: 2).storedValue() == 34)
        #expect(throws: InitializerRequirementError.rejected(-2)) {
            _ = try type(of: seed).init(value: -2)
        }
    }

    @Test func asyncThrowingInitializersUseSuspendingHandlers() async throws {
        #expect(
            try await useLinkedAsyncInitializerRequirement(
                RealAsyncInitializerRequirementProbe(value: 0)
            ) == 0
        )
        let stub = try Stub<any AsyncInitializerRequirementProbe>()
        await stub.when(initializer: {
            try await type(of: $0).init(value: any())
        }).then { (value: Int) async throws in
            await Task.yield()
            if value < 0 { throw InitializerRequirementError.rejected(value) }
        }
        stub.when { $0.storedValue() }.thenReturn(55)

        let seed: any AsyncInitializerRequirementProbe = stub()
        #expect(try await type(of: seed).init(value: 3).storedValue() == 55)
        await #expect(throws: InitializerRequirementError.rejected(-3)) {
            _ = try await type(of: seed).init(value: -3)
        }
    }

    @Test func asyncFailableInitializersChooseSuccessNilAndError() async throws {
        let stub = try Stub<any AsyncFailableInitializerRequirementProbe>()
        await stub.when(initializer: {
            try await type(of: $0).init(value: any())
        }).thenInitialize()
        await stub.when(initializer: {
            try await type(of: $0).init(value: equal(0))
        }).thenReturnNil()
        await stub.when(initializer: {
            try await type(of: $0).init(value: equal(-1))
        }).thenThrow(InitializerRequirementError.rejected(-1))
        stub.when { $0.storedValue() }.thenReturn(89)

        let seed: any AsyncFailableInitializerRequirementProbe = stub()
        let initialized = try await type(of: seed).init(value: 1)

        #expect(initialized?.storedValue() == 89)
        #expect(try await type(of: seed).init(value: 0) == nil)
        await #expect(throws: InitializerRequirementError.rejected(-1)) {
            _ = try await type(of: seed).init(value: -1)
        }
    }

    @Test func initializedValueOwnsTheRuntimeGraph() throws {
        #expect(
            useLinkedInitializerRequirement(
                RealInitializerRequirementProbe(value: "linked")
            ) == "real"
        )
        var stub: Stub<any InitializerRequirementProbe>? = try Stub()
        stub?.when(initializer: { type(of: $0).init(value: any()) }).thenInitialize()
        stub?.when { $0.storedValue() }.thenReturn("alive")
        let initialized = try #require(stub).withValue { value in
            type(of: value).init(value: "created")
        }

        stub = nil

        #expect(initialized.storedValue() == "alive")
    }

    @Test func classInitializersCreateDistinctPayloadObjects() throws {
        #expect(
            useLinkedClassInitializerRequirement(
                RealClassInitializerRequirementProbe()
            ) is RealClassInitializerRequirementProbe
        )
        let stub = try Stub<any ClassInitializerRequirementProbe>()
        stub.when(initializer: { type(of: $0).init() }).thenInitialize()

        let seed: any ClassInitializerRequirementProbe = stub()
        let first = type(of: seed).init()
        let second = type(of: seed).init()

        #expect(first !== second)
    }

    @Test func classFailableInitializersUseOptionalSelfStorage() throws {
        #expect(
            RealClassInitializerRequirementProbe(enabled: true) != nil
        )
        let stub = try Stub<any ClassInitializerRequirementProbe>()
        stub.when(initializer: {
            type(of: $0).init(enabled: any())
        }).then { (enabled: Bool) in
            enabled ? .initialize : .returnNil
        }

        let seed: any ClassInitializerRequirementProbe = stub()
        let first = try #require(type(of: seed).init(enabled: true))
        let second = try #require(type(of: seed).init(enabled: true))

        #expect(first !== second)
        #expect(type(of: seed).init(enabled: false) == nil)
    }

    @Test func inheritedInitializersReturnTheDerivedProtocolValue() throws {
        #expect(
            useLinkedChildInitializerRequirement(
                RealChildInitializerRequirementProbe(baseValue: 0)
            ) == 0
        )
        let stub = try Stub<any ChildInitializerRequirementProbe>()
        stub.when(initializer: {
            type(of: $0).init(baseValue: any())
        }).thenInitialize()
        stub.when { $0.storedValue() }.thenReturn(21)
        stub.when { $0.childValue() }.thenReturn(42)

        let seed: any ChildInitializerRequirementProbe = stub()
        let initialized = type(of: seed).init(baseValue: 1)

        #expect(initialized.storedValue() == 21)
        #expect(initialized.childValue() == 42)
    }
}

private func assertAssociatedTypeInitializerDescriptor<Argument>(
    _ method: MethodDescriptor,
    argumentType: Argument.Type,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let actualArgumentType = try #require(method.argumentTypes.first)
    #expect(method.kind == .initializer, sourceLocation: sourceLocation)
    #expect(method.argumentTypes.count == 1, sourceLocation: sourceLocation)
    #expect(
        ObjectIdentifier(actualArgumentType) == ObjectIdentifier(argumentType),
        sourceLocation: sourceLocation
    )
    #expect(
        method.argumentConventions == [.associatedType(name: "Element")],
        sourceLocation: sourceLocation
    )
    #expect(
        method.argumentDependencies == [.associatedType(name: "Element")],
        sourceLocation: sourceLocation
    )
    #expect(method.argumentOwnerships == [.owned], sourceLocation: sourceLocation)
    #expect(method.returnConvention == .selfType, sourceLocation: sourceLocation)
}
