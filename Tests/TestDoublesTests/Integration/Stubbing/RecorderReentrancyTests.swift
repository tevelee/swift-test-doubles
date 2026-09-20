import Foundation
import Testing
import TestDoubles

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    private enum RegistrationCallback {
        case description, hashing, equality
    }

    private struct ReentrantArgument: Hashable, CustomStringConvertible {
        let value: Int
        let callback: RegistrationCallback
        let onCallback: () -> Void

        var description: String {
            if callback == .description { onCallback() }
            return String(value)
        }

        func hash(into hasher: inout Hasher) {
            if callback == .hashing { onCallback() }
            hasher.combine(value)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            if lhs.callback == .equality { lhs.onCallback() }
            return lhs.value == rhs.value
        }
    }

    private struct ReentrantConformer: ManualStubConformer {
        let stub: ManualStub<Self>
        func lookup(_ argument: ReentrantArgument) -> Int { stub.call(argument) }
    }

    private func registerWithReentrantCallback(_ callback: RegistrationCallback) {
        alarm(10)
        defer { alarm(0) }
        let stub = ManualStub<ReentrantConformer>()
        let first = ReentrantArgument(value: 1, callback: callback) {
            _ = stub.history.callCount
        }
        let second = ReentrantArgument(value: 2, callback: callback) {
            _ = stub.history.callCount
        }
        stub.when { $0.lookup(Match.equal(first)) }.thenReturn(10)
        stub.when { $0.lookup(Match.equal(second)) }.thenReturn(20)
        precondition(stub().lookup(first) == 10)
        precondition(stub().lookup(second) == 20)
    }

    @Suite struct RecorderReentrancyExitTests {
        @Test func registrationDescriptionCanReadTheSameDouble() async {
            await #expect(processExitsWith: .success) {
                registerWithReentrantCallback(.description)
            }
        }

        @Test func registrationHashingCanReadTheSameDouble() async {
            await #expect(processExitsWith: .success) {
                registerWithReentrantCallback(.hashing)
            }
        }

        @Test func registrationEqualityCanReadTheSameDouble() async {
            await #expect(processExitsWith: .success) {
                registerWithReentrantCallback(.equality)
            }
        }

        @Test func registrationRetriesWithoutLosingNestedRegistrationsOrConsumption() async {
            await #expect(processExitsWith: .success) {
                alarm(10)
                defer { alarm(0) }
                let stub = ManualStub<ReentrantConformer>()
                let existing = (0 ..< 4).map {
                    ReentrantArgument(value: $0, callback: .description, onCallback: {})
                }
                for argument in existing {
                    stub.when { $0.lookup(Match.equal(argument)) }.thenReturn(argument.value)
                }
                let nested = ReentrantArgument(value: 20, callback: .description, onCallback: {})
                var reentered = false
                let outer = ReentrantArgument(value: 10, callback: .hashing) {
                    guard reentered == false else { return }
                    reentered = true
                    for argument in existing {
                        precondition(stub().lookup(argument) == argument.value)
                    }
                    stub.when { $0.lookup(Match.equal(nested)) }.thenReturn(20)
                }
                stub.when { $0.lookup(Match.equal(outer)) }.thenReturn(10)

                precondition(reentered)
                precondition(stub().lookup(outer) == 10)
                precondition(stub().lookup(nested) == 20)
                precondition(stub.history.callCount == 6)
                stub.verifyNoUnusedStubs()
            }
        }

        @Test func fatalDiagnosticCanReenterTheSameDouble() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                alarm(10)
                let double = ClosureDouble<Int, Int>()
                double.when { value in
                    _ = double.history.callCount
                    return value == 1
                }.thenFatalError("reentrant fatal diagnostic")
                _ = double(1)
            }
            let diagnostic = try #require(String(bytes: result.standardErrorContent, encoding: .utf8))
            #expect(diagnostic.contains("Explicit stub failure: reentrant fatal diagnostic"))
        }
    }
#endif
