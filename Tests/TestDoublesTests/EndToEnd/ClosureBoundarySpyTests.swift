import TestDoubles
import TestDoublesFixtures
import Testing

@Suite struct ClosureBoundarySpyTests {
    @Test func cFunctionPointersForwardThroughSpies() throws {
        let placeholder: ExternalCFunction = externalCIncrement
        let captor = Match.Capture<ExternalCFunction>()
        let spy = try Spy<any ExternalFunctionConventionService>(
            forwardingTo: RealExternalFunctionConventionService()
        )

        let returned = spy().cFunction(externalCDouble)

        #expect(returned(21) == 42)
        spy.verify(returning: placeholder) {
            $0.cFunction(captor.capture(using: placeholder))
        }
        let captured = try #require(captor.first)
        #expect(captured(21) == 42)
    }

    #if canImport(ObjectiveC)
        @Test func capturedBlockFunctionsForwardThroughSpies() throws {
            let placeholder: ExternalBlockFunction = { $0 }
            let captor = Match.Capture<ExternalBlockFunction>()
            let spy = try Spy<any ExternalFunctionConventionService>(
                forwardingTo: RealExternalFunctionConventionService()
            )
            let captured = Int32(21)

            let returned = spy().blockFunction { $0 + captured }

            #expect(returned(21) == 42)
            spy.verify(returning: placeholder) {
                $0.blockFunction(captor.capture(using: placeholder))
            }
            let recorded = try #require(captor.first)
            #expect(recorded(21) == 42)
        }
    #endif

    @Test func closureContainersForwardThroughSpies() throws {
        let placeholder: ExternalContainerClosure = { "\($0)" }
        let tuplePlaceholder: ExternalClosureTuple = (
            "placeholder",
            placeholder
        )
        let boxPlaceholder = ExternalClosureBox(
            label: "placeholder",
            transform: placeholder
        )
        let optionalCaptor = Match.Capture<ExternalContainerClosure?>()
        let spy = try Spy<any ExternalClosureContainerService>(
            forwardingTo: RealExternalClosureContainerService()
        )
        spy.when(returning: boxPlaceholder) {
            $0.nominal(Match.any(using: boxPlaceholder))
        }.thenForward()
        let service: any ExternalClosureContainerService = spy()
        let transform: ExternalContainerClosure = { "\($0 * 2)!" }

        let optional = service.optional(transform)
        let array = service.array([transform])
        let tuple = service.tuple(("tuple", transform))
        let box = service.nominal(
            ExternalClosureBox(label: "box", transform: transform)
        )

        #expect(optional?(21) == "42!")
        #expect(array.first?(21) == "42!")
        #expect(tuple.label == "tuple")
        #expect(tuple.transform(21) == "42!")
        #expect(box.label == "box")
        #expect(box.transform(21) == "42!")

        spy.verify(returning: Optional(placeholder)) {
            $0.optional(
                optionalCaptor.capture(using: Optional(placeholder))
            )
        }
        spy.verify(returning: [placeholder]) {
            $0.array(Match.any(using: [placeholder]))
        }
        spy.verify(returning: tuplePlaceholder) {
            $0.tuple(Match.any(using: tuplePlaceholder))
        }
        spy.verify(returning: boxPlaceholder) {
            $0.nominal(Match.any(using: boxPlaceholder))
        }

        let recordedOptional = try #require(optionalCaptor.first)
        #expect(recordedOptional?(21) == "42!")
    }
}
