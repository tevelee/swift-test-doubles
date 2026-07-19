import Testing
@testable import TestDoubles

private struct AsyncFailureProbeError: Error, Equatable {}

private protocol AsyncFailureProbe {
    func run() async throws -> Int
}

@Suite struct StubRecorderDiagnosticsTests {
    private func makeRecorder(
        methods: [MethodDescriptor] = []
    ) -> StubRecorder {
        StubRecorder(methods: methods)
    }

    private func makeMethod(
        name: String,
        kind: StubRequirementKind = .method,
        receiver: StubRequirementReceiver = .instance,
        origin: MethodDescriptor.Origin = .automatic,
        argumentTypes: [Any.Type] = [],
        returnType: Any.Type = String.self,
        returnConvention: WitnessValueConvention = .concrete,
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> MethodDescriptor {
        MethodDescriptor(
            kind: kind,
            receiver: receiver,
            origin: origin,
            name: name,
            index: 0,
            argumentTypes: argumentTypes,
            returnType: returnType,
            returnConvention: returnConvention,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    @Test func missingStubDiagnosticListsArgumentsAndSuggestion() {
        let recorder = makeRecorder()
        let method = makeMethod(name: "fetch(id:name:)", argumentTypes: [Int.self, String.self])

        let message = recorder.diagnosticMessage(
            title: "No stub configured",
            method: method,
            args: [42, "alice"],
            entries: []
        )

        #expect(message.contains("[TestDoubles] No stub configured for fetch(id:name:)"))
        #expect(message.contains("arg0: 42"))
        #expect(message.contains("arg1: \"alice\""))
        #expect(message.contains("Registered stubs:\n  <none>"))
        #expect(message.contains("Register behavior with `stub.when { ... }` before invoking"))
        #expect(
            message.contains(
                "stub.when { $0.fetch(id: equal(42), name: equal(\"alice\")) }.thenReturn(...)"
            )
        )
    }

    @Test func explicitRequirementDiagnosticOmitsTheSuggestion() {
        let recorder = makeRecorder()
        let method = makeMethod(name: "requirement_0", origin: .explicit)

        let message = recorder.diagnosticMessage(
            title: "No matching stub",
            method: method,
            args: [],
            entries: []
        )

        #expect(message.contains("  <no arguments>"))
        #expect(message.contains("Suggested:") == false)
    }

    @Test func suggestionsUseStaticAndGeneratedResultBuilders() {
        let recorder = makeRecorder()
        let staticMethod = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(name: "name()", receiver: .metatype),
            args: [],
            entries: []
        )
        let initializer = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(
                name: "init(id:)",
                kind: .initializer,
                receiver: .metatype,
                argumentTypes: [Int.self],
                returnConvention: .selfType
            ),
            args: [1],
            entries: []
        )
        let dynamicSelf = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(name: "duplicate()", returnConvention: .selfType),
            args: [],
            entries: []
        )

        #expect(staticMethod.contains("stub.when { type(of: $0).name() }.thenReturn(...)"))
        #expect(
            initializer.contains(
                "stub.when(initializer: { type(of: $0).init(id: equal(1)) }).thenInitialize()"
            )
        )
        #expect(
            dynamicSelf.contains(
                "stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()"
            )
        )
    }

    @Test func diagnosticListsRegisteredEntriesBySignature() {
        let recorder = makeRecorder(methods: [makeMethod(name: "ping()")])
        let entry = StubRecorder.StubEntry(
            matchers: [AnyMatcher()],
            diagnosticSignature: "ping(any())",
            behavior: .fixed(.success("pong"))
        )

        let message = recorder.diagnosticMessage(
            title: "No matching stub",
            method: makeMethod(name: "ping()"),
            args: ["probe"],
            entries: [entry]
        )

        #expect(message.contains("Registered stubs:\n  ping(any())"))
        #expect(message.contains("whose matchers accept these arguments"))
    }

    @Test func suggestionsIncludeRequirementEffectsAndVoidConfiguration() {
        let recorder = makeRecorder()
        let asyncThrowing = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(
                name: "load(id:)",
                argumentTypes: [Int.self],
                isThrowing: true,
                isAsync: true
            ),
            args: [42],
            entries: []
        )
        let void = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(name: "reset()", returnType: Void.self),
            args: [],
            entries: []
        )

        #expect(
            asyncThrowing.contains(
                "await stub.when { try await $0.load(id: equal(42)) }.thenReturn(...)"
            )
        )
        #expect(void.contains("stub.when { $0.reset() }.thenDoNothing()"))
    }

    @Test func suggestionsHandleUnlabeledAndUnparenthesizedNames() {
        let recorder = makeRecorder()

        let unlabeled = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(name: "add(_:_:)", argumentTypes: [Int.self, Int.self]),
            args: [1, 2],
            entries: []
        )
        #expect(unlabeled.contains("stub.when { $0.add(equal(1), equal(2)) }.thenReturn(...)"))

        let property = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(name: "count", argumentTypes: [Int.self]),
            args: [3],
            entries: []
        )
        #expect(property.contains("stub.when { $0.count(equal(3)) }.thenReturn(...)"))

        let mismatchedLabels = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(name: "route(a:)", argumentTypes: [Int.self, Int.self]),
            args: [1, 2],
            entries: []
        )
        #expect(mismatchedLabels.contains("stub.when { $0.route(equal(1), equal(2)) }.thenReturn(...)"))
    }

    @Test func suggestedLiteralsEscapeStringsAndCharacters() {
        let recorder = makeRecorder()
        let message = recorder.diagnosticMessage(
            title: "No stub configured",
            method: makeMethod(
                name: "mark(text:grade:)",
                argumentTypes: [String.self, Character.self]
            ),
            args: ["say \"hi\"", Character("A")],
            entries: []
        )

        #expect(message.contains("text: equal(\"say \\\"hi\\\"\")"))
        #expect(message.contains("grade: equal(\"A\")"))
    }

    @Test func lookupsFailSoftlyForUnknownIndices() {
        let recorder = makeRecorder(methods: [makeMethod(name: "ping()")])

        #expect(recorder.runtimeMethod(for: 5) == nil)
        #expect(recorder.modifyDispatchMethods(forGetterIndex: 5) == nil)
        #expect(recorder.returnValueMatchesRuntimeType("value", for: 5) == false)
    }

    @Test func orderedDiagnosticListsAnEmptyRecordedCallOrder() {
        let recorder = makeRecorder(methods: [makeMethod(name: "ping()")])
        let expectation = RecordedCall(
            methodIndex: 0,
            name: "ping()",
            args: [],
            matchers: []
        )

        let failure = recorder.orderedVerificationFailure(for: [expectation])

        #expect(failure?.contains("expectation 1 was not found in the recorded calls") == true)
        #expect(failure?.contains("Recorded call order:\n  <none>") == true)
    }

    @Test func immediateHandlersOnAsyncRequirementsPropagateThrownErrors() async throws {
        let stub = try Stub<any AsyncFailureProbe>(
            .method(returning: Int.self, isThrowing: true, isAsync: true)
        )
        await stub.when { try await $0.run() }.then { () throws -> Int in
            throw AsyncFailureProbeError()
        }

        let probe = stub()
        await #expect(throws: AsyncFailureProbeError.self) {
            _ = try await probe.run()
        }
    }
}
