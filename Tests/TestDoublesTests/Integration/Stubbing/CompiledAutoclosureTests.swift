import Testing
import TestDoubles

private enum LogLevel: Int, Comparable, Sendable {
    case info
    case error

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

private protocol DeferredLogger {
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, file: String, line: Int)
    func trace(_ message: @autoclosure () throws -> String) rethrows
}

private struct DeferredLoggerStubConformer: DeferredLogger, ManualStubConformer {
    let stub: CompiledStub<Self>

    func log(_ level: LogLevel, _ message: @autoclosure () -> String, file: String, line: Int) {
        stub.call(level, stub.deferredArgument(at: 1, message), file, line)
    }

    func trace(_ message: @autoclosure () throws -> String) rethrows {
        stub.call(try stub.deferredArgument(at: 0, message))
    }
}

private struct TraceFailure: Error {}

/// An `@autoclosure` argument is evaluated after every other argument, so its
/// matcher must be filed under its own position rather than trailing them.
@Suite struct CompiledAutoclosureTests {
    @Test func matchersInsideAnAutoclosureKeepTheirArgumentPosition() {
        let logger = CompiledStub<DeferredLoggerStubConformer>()
        let logs = logger.when {
            $0.log(Match.any(), Match.any(), file: Match.any(), line: Match.any())
        }
        logs.thenDoNothing()

        logger().log(.error, "charge failed: offline", file: "Checkout.swift", line: 89)
        logger().log(.info, "charging 10", file: "Checkout.swift", line: 81)

        logger.verify {
            $0.log(
                Match.equal(.error),
                Match.containsSubstring("offline"),
                file: Match.any(),
                line: Match.any()
            )
        }
        logger.verify(.never) {
            $0.log(
                Match.equal(.info),
                Match.containsSubstring("offline"),
                file: Match.any(),
                line: Match.any()
            )
        }
        let arguments: [(LogLevel, String, String, Int)] = logs.arguments()
        #expect(arguments.map(\.1) == ["charge failed: offline", "charging 10"])
    }

    @Test func mixedLiteralsLocateTheDeferredMatcher() {
        let logger = CompiledStub<DeferredLoggerStubConformer>()
        logger.when {
            $0.log(.error, Match.hasPrefix("charge"), file: "Checkout.swift", line: 89)
        }.thenDoNothing()

        logger().log(.error, "charge failed", file: "Checkout.swift", line: 89)

        logger.verify {
            $0.log(.error, Match.hasPrefix("charge"), file: "Checkout.swift", line: 89)
        }
    }

    @Test func throwingAutoclosuresPropagateFromTheForwarder() throws {
        let logger = CompiledStub<DeferredLoggerStubConformer>()
        logger.when { $0.trace(Match.any()) }.thenDoNothing()

        try logger().trace("ready")
        #expect(throws: TraceFailure.self) {
            try logger().trace(try { throw TraceFailure() }())
        }

        logger.verify { $0.trace(Match.equal("ready")) }
    }
}
