import Testing
@testable import TestDoubles

// Forwarding's target metadata and witness-table pair are not reserved a
// fixed register pair: each independently lands wherever the target
// witness's own competitive register allocation puts it -- exactly matching
// the real target function's compiled calling convention, since a witness
// call's hidden metadata/witness-table parameters are placed immediately
// after its visible arguments, wherever that boundary falls. When visible
// arguments fill all available registers, metadata and/or witness table
// spill to the caller's outgoing stack right along with them, and
// `td_swift_invoke_witness`'s two explicit outgoing-stack-word parameters
// carry those spilled words to the real call.
//
// The exact argument count that starts spilling differs per architecture
// (arm64: 8 argument registers; x86_64: 6), so this whole suite is
// architecture-gated like AsyncStackSpyForwardingTests.
#if arch(x86_64) || arch(arm64)

    #if arch(x86_64)
        // x86_64: 6 argument registers.
        protocol FitsSpillSpyService: Sendable {
            func call(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int) -> Int
        }

        protocol OneWordSpillSpyService: Sendable {
            func call(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int) -> Int
        }

        protocol TwoWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
            ) -> Int
        }

        protocol ThrowingTwoWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
            ) throws -> Int
        }

        protocol ThreeWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int
            ) -> Int
        }
    #else
        // arm64: 8 argument registers.
        protocol FitsSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
            ) -> Int
        }

        protocol OneWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int
            ) -> Int
        }

        protocol TwoWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int, _ a7: Int
            ) -> Int
        }

        protocol ThrowingTwoWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int, _ a7: Int
            ) throws -> Int
        }

        protocol ThreeWordSpillSpyService: Sendable {
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int, _ a7: Int, _ a8: Int
            ) -> Int
        }
    #endif

    private enum SyncSpillForwardingError: Error, Equatable {
        case rejected(Int)
    }

    struct RealFitsSpillSpyService: FitsSpillSpyService {
        #if arch(x86_64)
            func call(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int) -> Int {
                a0 + a1 + a2 + a3
            }
        #else
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4 + a5
            }
        #endif
    }

    struct RealOneWordSpillSpyService: OneWordSpillSpyService {
        #if arch(x86_64)
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4
            }
        #else
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4 + a5 + a6
            }
        #endif
    }

    struct RealTwoWordSpillSpyService: TwoWordSpillSpyService {
        #if arch(x86_64)
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4 + a5
            }
        #else
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int, _ a7: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7
            }
        #endif
    }

    struct RealThrowingTwoWordSpillSpyService: ThrowingTwoWordSpillSpyService {
        #if arch(x86_64)
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int
            ) throws -> Int {
                let sum = a0 + a1 + a2 + a3 + a4 + a5
                guard sum >= 0 else { throw SyncSpillForwardingError.rejected(sum) }
                return sum
            }
        #else
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int, _ a7: Int
            ) throws -> Int {
                let sum = a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7
                guard sum >= 0 else { throw SyncSpillForwardingError.rejected(sum) }
                return sum
            }
        #endif
    }

    struct RealThreeWordSpillSpyService: ThreeWordSpillSpyService {
        #if arch(x86_64)
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4 + a5 + a6
            }
        #else
            func call(
                _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int,
                _ a6: Int, _ a7: Int, _ a8: Int
            ) -> Int {
                a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8
            }
        #endif
    }

    @Suite struct SyncStackSpySpillForwardingTests {
        @Test func registerOnlyArgumentsStillForward() throws {
            let spy = try Spy<any FitsSpillSpyService>(
                forwardingTo: RealFitsSpillSpyService()
            )
            let service: any FitsSpillSpyService = spy()
            #if arch(x86_64)
                #expect(service.call(1, 2, 3, 4) == 10)
            #else
                #expect(service.call(1, 2, 3, 4, 5, 6) == 21)
            #endif
        }

        @Test func oneSpilledWordForwards() throws {
            // The one spilled word here is the target's own witness-table
            // pointer (metadata still fits in the last register) -- not a
            // visible argument, proving the spill transport works for
            // forwarding's own hidden payload, not just user arguments.
            let spy = try Spy<any OneWordSpillSpyService>(
                forwardingTo: RealOneWordSpillSpyService()
            )
            let service: any OneWordSpillSpyService = spy()
            #if arch(x86_64)
                #expect(service.call(1, 2, 3, 4, 5) == 15)
            #else
                #expect(service.call(1, 2, 3, 4, 5, 6, 7) == 28)
            #endif
        }

        @Test func twoSpilledWordsForward() throws {
            // Both metadata and witness table spill here (visible arguments
            // fill every argument register) -- the second word this whole
            // capability exists for.
            let spy = try Spy<any TwoWordSpillSpyService>(
                forwardingTo: RealTwoWordSpillSpyService()
            )
            let service: any TwoWordSpillSpyService = spy()
            #if arch(x86_64)
                #expect(service.call(1, 2, 3, 4, 5, 6) == 21)
            #else
                #expect(service.call(1, 2, 3, 4, 5, 6, 7, 8) == 36)
            #endif
        }

        @Test func throwingWithTwoSpilledWordsForwards() throws {
            let spy = try Spy<any ThrowingTwoWordSpillSpyService>(
                forwardingTo: RealThrowingTwoWordSpillSpyService()
            )
            let service: any ThrowingTwoWordSpillSpyService = spy()
            #if arch(x86_64)
                #expect(try service.call(1, 2, 3, 4, 5, 6) == 21)
                let error = #expect(throws: SyncSpillForwardingError.self) {
                    _ = try service.call(-100, 2, 3, 4, 5, 6)
                }
                #expect(error == .rejected(-80))
            #else
                #expect(try service.call(1, 2, 3, 4, 5, 6, 7, 8) == 36)
                let error = #expect(throws: SyncSpillForwardingError.self) {
                    _ = try service.call(-100, 2, 3, 4, 5, 6, 7, 8)
                }
                #expect(error == .rejected(-65))
            #endif
        }

        @Test func threeSpilledWordsRemainFailClosed() {
            let error = #expect(throws: StubError.self) {
                _ = try Spy<any ThreeWordSpillSpyService>(
                    forwardingTo: RealThreeWordSpillSpyService()
                )
            }
            #expect(
                error?.description.contains(
                    "needs more outgoing stack transport"
                ) == true
            )
        }
    }

#endif
