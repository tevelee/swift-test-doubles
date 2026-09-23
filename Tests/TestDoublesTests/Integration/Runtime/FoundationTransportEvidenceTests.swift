import Foundation
import Testing
import TestDoubles

// Darwin's Foundation is built with library evolution, so the catalog's
// transport facts hold for every compiler there. Elsewhere they need the
// compiler that emits the corresponding adapters.
#if !os(WASI) && (canImport(Darwin) || compiler(>=6.4))
    protocol FoundationTransportClock {
        var now: Date { get }
        func schedule(title: String, at date: Date, repeats: Bool) -> Bool
    }

    struct LiveFoundationTransportClock: FoundationTransportClock {
        var now: Date { Date() }
        func schedule(title: String, at date: Date, repeats: Bool) -> Bool { true }
    }

    protocol FoundationTransportFiles {
        func contents(of directory: URL) throws -> [URL]
        func get(_ url: URL, headers: [String: String]) -> Data
    }

    struct LiveFoundationTransportFiles: FoundationTransportFiles {
        func contents(of directory: URL) throws -> [URL] { [] }
        func get(_ url: URL, headers: [String: String]) -> Data { Data() }
    }

    protocol FoundationTransportUsers {
        func name(for id: UUID) -> String
    }

    struct LiveFoundationTransportUsers: FoundationTransportUsers {
        func name(for id: UUID) -> String { id.uuidString }
    }

    /// The compiler-established transport of common Foundation values settles
    /// results and arguments without a recording call to calibrate them.
    @Suite struct FoundationTransportEvidenceTests {
        @Test func dateResultsNeedNoExplicitRequirement() throws {
            let clock = try Stub<any FoundationTransportClock>(
                discoveringFrom: LiveFoundationTransportClock()
            )
            let fixed = Date(timeIntervalSince1970: 1_700_000_000)
            clock.when { $0.now }.thenReturn(fixed)

            #expect(clock().now == fixed)
        }

        @Test func literalFoundationArgumentsNeedNoMatchExpressions() throws {
            let files = try Stub<any FoundationTransportFiles>(
                discoveringFrom: LiveFoundationTransportFiles()
            )
            let directory = URL(filePath: "/tmp/documents")
            files.when { try $0.contents(of: directory) }
                .thenReturn([directory.appending(path: "a.txt")])
            files.when { $0.get(directory, headers: [:]) }.thenReturn(Data([1]))

            #expect(try files().contents(of: directory).count == 1)
            #expect(files().get(directory, headers: [:]) == Data([1]))
            files.verify { $0.get(directory, headers: [:]) }
        }

        @Test func literalsAndMatchersMixWithFoundationArguments() throws {
            let clock = try Stub<any FoundationTransportClock>(
                discoveringFrom: LiveFoundationTransportClock()
            )
            let start = Date(timeIntervalSince1970: 0)
            clock.when {
                $0.schedule(title: Match.any(), at: Match.greaterThan(start), repeats: false)
            }.thenReturn(true)
            clock.when {
                $0.schedule(title: Match.any(), at: Match.any(), repeats: Match.any())
            }.thenReturn(false)

            #expect(clock().schedule(title: "x", at: .now, repeats: false))
            #expect(clock().schedule(title: "x", at: .now, repeats: true) == false)
        }

        @Test func spiesForwardFoundationArgumentsWithoutConfiguration() {
            let spy: Spy<any FoundationTransportUsers> = Spy.make(
                forwardingTo: LiveFoundationTransportUsers()
            )
            let id = UUID()

            #expect(spy().name(for: id) == id.uuidString)
            spy.verify { $0.name(for: id) }
        }
    }
#endif
