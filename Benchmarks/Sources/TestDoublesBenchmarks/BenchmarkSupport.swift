import Foundation

let benchmarkControlName = "control.protocol-dispatch"

struct TimedMeasurement {
    let elapsedNanoseconds: Double
    let checksum: UInt64
}

struct BenchmarkDefinition {
    let name: String
    let preExpansionComparable: Bool
    let pilotIterations: Int
    let maximumIterations: Int
    let measure: (Int) async throws -> TimedMeasurement
}

struct BenchmarkResult: Codable {
    let name: String
    let iterations: Int
    let samples: [Double]
    let medianNanosecondsPerOperation: Double
    let p90NanosecondsPerOperation: Double
    let checksum: UInt64
}

struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let harnessVersion: Int
    let revision: String
    let generatedAt: String
    let operatingSystem: String
    let architecture: String
    let compiler: String
    let sampleCount: Int
    let targetMilliseconds: Double
    let benchmarks: [BenchmarkResult]
}

enum BenchmarkSuite: String {
    case all
    case comparable
}

struct RunOptions {
    var suite = BenchmarkSuite.all
    var sampleCount = 7
    var targetMilliseconds = 100.0
    var outputPath: String?
    var quiet = false

    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
                case "--suite":
                    let value = try argumentValue(after: index, in: arguments)
                    guard let suite = BenchmarkSuite(rawValue: value) else {
                        throw BenchmarkCommandError("Unknown benchmark suite '\(value)'.")
                    }
                    options.suite = suite
                    index += 2
                case "--samples":
                    let value = try argumentValue(after: index, in: arguments)
                    guard let count = Int(value), count >= 3 else {
                        throw BenchmarkCommandError("--samples must be at least 3.")
                    }
                    options.sampleCount = count
                    index += 2
                case "--target-ms":
                    let value = try argumentValue(after: index, in: arguments)
                    guard let milliseconds = Double(value), milliseconds > 0 else {
                        throw BenchmarkCommandError("--target-ms must be positive.")
                    }
                    options.targetMilliseconds = milliseconds
                    index += 2
                case "--output":
                    options.outputPath = try argumentValue(after: index, in: arguments)
                    index += 2
                case "--quiet":
                    options.quiet = true
                    index += 1
                default:
                    throw BenchmarkCommandError("Unknown argument '\(arguments[index])'.")
            }
        }

        return options
    }
}

struct CompareOptions {
    let baselinePath: String
    let candidatePath: String
    var maximumRegressionPercent = 20.0

    static func parse(_ arguments: [String]) throws -> Self {
        guard arguments.count >= 2 else {
            throw BenchmarkCommandError(
                "compare requires baseline and candidate result paths."
            )
        }

        var options = Self(
            baselinePath: arguments[0],
            candidatePath: arguments[1]
        )
        var index = 2
        while index < arguments.count {
            switch arguments[index] {
                case "--max-regression-percent":
                    let value = try argumentValue(after: index, in: arguments)
                    guard let percent = Double(value), percent >= 0 else {
                        throw BenchmarkCommandError(
                            "--max-regression-percent must not be negative."
                        )
                    }
                    options.maximumRegressionPercent = percent
                    index += 2
                default:
                    throw BenchmarkCommandError("Unknown argument '\(arguments[index])'.")
            }
        }
        return options
    }
}

struct BenchmarkCommandError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func argumentValue(after index: Int, in arguments: [String]) throws -> String {
    let valueIndex = index + 1
    guard arguments.indices.contains(valueIndex) else {
        throw BenchmarkCommandError("Missing value after '\(arguments[index])'.")
    }
    return arguments[valueIndex]
}

func runBenchmarks(
    _ definitions: [BenchmarkDefinition],
    options: RunOptions
) async throws -> BenchmarkReport {
    let suiteDefinitions: [BenchmarkDefinition]
    switch options.suite {
        case .all:
            suiteDefinitions = definitions
        case .comparable:
            suiteDefinitions = definitions.filter(\.preExpansionComparable)
    }
    let selected =
        suiteDefinitions.filter { !$0.name.contains(".construct.") }
        + suiteDefinitions.filter { $0.name.contains(".construct.") }
    guard selected.contains(where: { $0.name == benchmarkControlName }) else {
        throw BenchmarkCommandError("The benchmark control is missing.")
    }

    var results: [BenchmarkResult] = []
    for definition in selected {
        let pilot = try await definition.measure(definition.pilotIterations)
        let pilotNanosecondsPerOperation = max(
            pilot.elapsedNanoseconds / Double(definition.pilotIterations),
            1
        )
        let targetNanoseconds = options.targetMilliseconds * 1_000_000
        let calibratedIterations = min(
            definition.maximumIterations,
            max(1, Int(targetNanoseconds / pilotNanosecondsPerOperation))
        )

        _ = try await definition.measure(calibratedIterations)

        var samples: [Double] = []
        var checksum = pilot.checksum
        for _ in 0 ..< options.sampleCount {
            let measurement = try await definition.measure(calibratedIterations)
            samples.append(
                measurement.elapsedNanoseconds / Double(calibratedIterations)
            )
            checksum ^= measurement.checksum
        }

        let sortedSamples = samples.sorted()
        let median = percentile(0.5, in: sortedSamples)
        let p90 = percentile(0.9, in: sortedSamples)
        let result = BenchmarkResult(
            name: definition.name,
            iterations: calibratedIterations,
            samples: samples,
            medianNanosecondsPerOperation: median,
            p90NanosecondsPerOperation: p90,
            checksum: checksum
        )
        results.append(result)

        if !options.quiet {
            let paddedName = definition.name.padding(
                toLength: 42,
                withPad: " ",
                startingAt: 0
            )
            let operationsPerSecond = 1_000_000_000 / median
            print(
                "\(paddedName) \(formatNanoseconds(median))  "
                    + "\(formatOperations(operationsPerSecond)) ops/s"
            )
        }
    }

    let report = BenchmarkReport(
        schemaVersion: 1,
        harnessVersion: 1,
        revision: benchmarkRevision,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        operatingSystem: benchmarkOperatingSystem,
        architecture: benchmarkArchitecture,
        compiler: benchmarkCompiler,
        sampleCount: options.sampleCount,
        targetMilliseconds: options.targetMilliseconds,
        benchmarks: results
    )

    if let outputPath = options.outputPath {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    return report
}

func compareBenchmarks(options: CompareOptions) throws {
    let decoder = JSONDecoder()
    let baseline = try decoder.decode(
        BenchmarkReport.self,
        from: Data(contentsOf: URL(fileURLWithPath: options.baselinePath))
    )
    let candidate = try decoder.decode(
        BenchmarkReport.self,
        from: Data(contentsOf: URL(fileURLWithPath: options.candidatePath))
    )
    guard baseline.schemaVersion == 1, candidate.schemaVersion == 1 else {
        throw BenchmarkCommandError("Unsupported benchmark result schema.")
    }
    guard baseline.harnessVersion == candidate.harnessVersion,
        baseline.operatingSystem == candidate.operatingSystem,
        baseline.architecture == candidate.architecture,
        baseline.compiler == candidate.compiler,
        baseline.sampleCount == candidate.sampleCount,
        baseline.targetMilliseconds == candidate.targetMilliseconds
    else {
        throw BenchmarkCommandError(
            "Benchmark reports were produced by incompatible environments or settings."
        )
    }

    let baselineByName = Dictionary(
        uniqueKeysWithValues: baseline.benchmarks.map { ($0.name, $0) }
    )
    let candidateByName = Dictionary(
        uniqueKeysWithValues: candidate.benchmarks.map { ($0.name, $0) }
    )
    guard let baselineControl = baselineByName[benchmarkControlName],
        let candidateControl = candidateByName[benchmarkControlName]
    else {
        throw BenchmarkCommandError(
            "Both reports must contain '\(benchmarkControlName)'."
        )
    }

    let controlRatio =
        candidateControl.medianNanosecondsPerOperation
        / baselineControl.medianNanosecondsPerOperation
    var regressions: [String] = []

    print("| Benchmark | Baseline | Candidate | Normalized change |")
    print("| --- | ---: | ---: | ---: |")
    for baselineResult in baseline.benchmarks
    where baselineResult.name != benchmarkControlName {
        guard let candidateResult = candidateByName[baselineResult.name] else {
            throw BenchmarkCommandError(
                "Candidate report is missing '\(baselineResult.name)'."
            )
        }
        let rawRatio =
            candidateResult.medianNanosecondsPerOperation
            / baselineResult.medianNanosecondsPerOperation
        let normalizedChange = (rawRatio / controlRatio - 1) * 100
        print(
            "| \(baselineResult.name)"
                + " | \(formatNanoseconds(baselineResult.medianNanosecondsPerOperation))"
                + " | \(formatNanoseconds(candidateResult.medianNanosecondsPerOperation))"
                + " | \(formatPercent(normalizedChange)) |"
        )
        if normalizedChange > options.maximumRegressionPercent {
            regressions.append(baselineResult.name)
        }
    }

    print(
        "\nDirect-dispatch control changed by "
            + "\(formatPercent((controlRatio - 1) * 100)); "
            + "reported benchmark changes are normalized by that ratio."
    )

    guard regressions.isEmpty else {
        throw BenchmarkCommandError(
            "Performance regression above "
                + "\(formatPercent(options.maximumRegressionPercent)): "
                + regressions.joined(separator: ", ")
        )
    }
}

func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double {
    guard !sortedValues.isEmpty else { return 0 }
    let position = Int(
        (percentile * Double(sortedValues.count - 1)).rounded()
    )
    return sortedValues[position]
}

func elapsedNanoseconds(
    from start: ContinuousClock.Instant,
    to end: ContinuousClock.Instant
) -> Double {
    let components = start.duration(to: end).components
    return Double(components.seconds) * 1_000_000_000
        + Double(components.attoseconds) / 1_000_000_000
}

func formatNanoseconds(_ nanoseconds: Double) -> String {
    if nanoseconds >= 1_000_000 {
        return String(format: "%.2f ms", nanoseconds / 1_000_000)
    }
    if nanoseconds >= 1_000 {
        return String(format: "%.2f us", nanoseconds / 1_000)
    }
    return String(format: "%.2f ns", nanoseconds)
}

func formatOperations(_ operations: Double) -> String {
    if operations >= 1_000_000 {
        return String(format: "%.2fM", operations / 1_000_000)
    }
    if operations >= 1_000 {
        return String(format: "%.2fK", operations / 1_000)
    }
    return String(format: "%.2f", operations)
}

func formatPercent(_ percent: Double) -> String {
    String(format: "%+.1f%%", percent)
}

private var benchmarkOperatingSystem: String {
    #if os(macOS)
        "macOS"
    #elseif os(Linux)
        "Linux"
    #elseif os(Android)
        "Android"
    #else
        "unknown"
    #endif
}

private var benchmarkArchitecture: String {
    #if arch(arm64)
        "arm64"
    #elseif arch(x86_64)
        "x86_64"
    #else
        "unknown"
    #endif
}

private var benchmarkCompiler: String {
    ProcessInfo.processInfo.environment[
        "TEST_DOUBLES_BENCHMARK_COMPILER"
    ] ?? "unknown"
}

private var benchmarkRevision: String {
    ProcessInfo.processInfo.environment[
        "TEST_DOUBLES_BENCHMARK_REVISION"
    ] ?? "unknown"
}
