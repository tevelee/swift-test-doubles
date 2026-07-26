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
    var sampleCount = 21
    var targetMilliseconds = 100.0
    var filter: String?
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
                case "--filter":
                    options.filter = try argumentValue(after: index, in: arguments)
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
    let reportPairs: [BenchmarkReportPair]
    var maximumRegressionPercent = 20.0

    static func parse(_ arguments: [String]) throws -> Self {
        var reportPaths: [String] = []
        var maximumRegressionPercent = 20.0
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
                case "--max-regression-percent":
                    let value = try argumentValue(after: index, in: arguments)
                    guard let percent = Double(value), percent >= 0 else {
                        throw BenchmarkCommandError(
                            "--max-regression-percent must not be negative."
                        )
                    }
                    maximumRegressionPercent = percent
                    index += 2
                default:
                    guard !arguments[index].hasPrefix("--") else {
                        throw BenchmarkCommandError("Unknown argument '\(arguments[index])'.")
                    }
                    reportPaths.append(arguments[index])
                    index += 1
            }
        }

        guard reportPaths.count >= 2, reportPaths.count.isMultiple(of: 2) else {
            throw BenchmarkCommandError(
                "compare requires one or more baseline/candidate result path pairs."
            )
        }

        let reportPairs = stride(from: 0, to: reportPaths.count, by: 2).map {
            BenchmarkReportPair(
                baselinePath: reportPaths[$0],
                candidatePath: reportPaths[$0 + 1]
            )
        }
        guard reportPairs.count == 1 || !reportPairs.count.isMultiple(of: 2) else {
            throw BenchmarkCommandError(
                "compare requires an odd number of report pairs when using multiple trials."
            )
        }

        return Self(
            reportPairs: reportPairs,
            maximumRegressionPercent: maximumRegressionPercent
        )
    }
}

struct BenchmarkReportPair {
    let baselinePath: String
    let candidatePath: String
}

struct BenchmarkComparisonTrial {
    let controlChangePercent: Double
    let benchmarkChanges: [BenchmarkChange]
    let settings: BenchmarkComparisonSettings
}

struct BenchmarkComparisonSummary {
    let medianControlChangePercent: Double
    let medianBenchmarkChanges: [BenchmarkChange]
}

struct BenchmarkChange {
    let name: String
    let normalizedChangePercent: Double
}

struct BenchmarkComparisonSettings: Equatable {
    let harnessVersion: Int
    let operatingSystem: String
    let architecture: String
    let compiler: String
    let sampleCount: Int
    let targetMilliseconds: Double
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
    let filteredDefinitions: [BenchmarkDefinition]
    if let filter = options.filter {
        filteredDefinitions = suiteDefinitions.filter {
            $0.name == benchmarkControlName || $0.name.contains(filter)
        }
    } else {
        filteredDefinitions = suiteDefinitions
    }
    let selected =
        filteredDefinitions.filter { !$0.name.contains(".construct.") }
        + filteredDefinitions.filter { $0.name.contains(".construct.") }
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
    let trials = try options.reportPairs.map(compareBenchmarkReports)
    let summary = try summarizeBenchmarkComparisonTrials(trials)
    var regressions: [String] = []

    print("| Benchmark | " + trialColumnNames(count: trials.count) + " | Median normalized change |")
    print("| --- | " + trialColumnSeparators(count: trials.count) + " | ---: |")
    for index in summary.medianBenchmarkChanges.indices {
        let changes = trials.map { $0.benchmarkChanges[index].normalizedChangePercent }
        let medianChange = summary.medianBenchmarkChanges[index].normalizedChangePercent
        print(
            "| \(summary.medianBenchmarkChanges[index].name)"
                + " | \(changes.map(formatPercent).joined(separator: " | "))"
                + " | \(formatPercent(medianChange)) |"
        )
        if medianChange > options.maximumRegressionPercent {
            regressions.append(summary.medianBenchmarkChanges[index].name)
        }
    }

    print(
        "\nDirect-dispatch control changed by "
            + "\(formatPercent(summary.medianControlChangePercent)) at the median across "
            + "\(trials.count) paired trial\(trials.count == 1 ? "" : "s"); "
            + "each trial is normalized by its own control ratio."
    )

    guard regressions.isEmpty else {
        throw BenchmarkCommandError(
            "Performance regression above "
                + "\(formatPercent(options.maximumRegressionPercent)): "
                + regressions.joined(separator: ", ")
        )
    }
}

func summarizeBenchmarkComparisonTrials(
    _ trials: [BenchmarkComparisonTrial]
) throws -> BenchmarkComparisonSummary {
    guard let firstTrial = trials.first else {
        throw BenchmarkCommandError("compare requires at least one report pair.")
    }

    for trial in trials.dropFirst() {
        guard trial.settings == firstTrial.settings else {
            throw BenchmarkCommandError(
                "Benchmark report pairs were produced by incompatible environments or settings."
            )
        }
        guard trial.benchmarkChanges.map(\.name) == firstTrial.benchmarkChanges.map(\.name) else {
            throw BenchmarkCommandError(
                "Benchmark report pairs contain different comparable workloads."
            )
        }
    }

    let medianBenchmarkChanges = firstTrial.benchmarkChanges.indices.map { index in
        BenchmarkChange(
            name: firstTrial.benchmarkChanges[index].name,
            normalizedChangePercent: median(
                of: trials.map { $0.benchmarkChanges[index].normalizedChangePercent }
            )
        )
    }
    return BenchmarkComparisonSummary(
        medianControlChangePercent: median(of: trials.map(\.controlChangePercent)),
        medianBenchmarkChanges: medianBenchmarkChanges
    )
}

func compareBenchmarkReports(
    reportPair: BenchmarkReportPair
) throws -> BenchmarkComparisonTrial {
    let decoder = JSONDecoder()
    let baseline = try decoder.decode(
        BenchmarkReport.self,
        from: Data(contentsOf: URL(fileURLWithPath: reportPair.baselinePath))
    )
    let candidate = try decoder.decode(
        BenchmarkReport.self,
        from: Data(contentsOf: URL(fileURLWithPath: reportPair.candidatePath))
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
    let benchmarkChanges: [BenchmarkChange] = try baseline.benchmarks.compactMap { baselineResult in
        guard baselineResult.name != benchmarkControlName else { return nil }
        guard let candidateResult = candidateByName[baselineResult.name] else {
            throw BenchmarkCommandError(
                "Candidate report is missing '\(baselineResult.name)'."
            )
        }
        let rawRatio =
            candidateResult.medianNanosecondsPerOperation
            / baselineResult.medianNanosecondsPerOperation
        let normalizedChange = (rawRatio / controlRatio - 1) * 100
        return BenchmarkChange(
            name: baselineResult.name,
            normalizedChangePercent: normalizedChange
        )
    }

    return BenchmarkComparisonTrial(
        controlChangePercent: (controlRatio - 1) * 100,
        benchmarkChanges: benchmarkChanges,
        settings: BenchmarkComparisonSettings(
            harnessVersion: baseline.harnessVersion,
            operatingSystem: baseline.operatingSystem,
            architecture: baseline.architecture,
            compiler: baseline.compiler,
            sampleCount: baseline.sampleCount,
            targetMilliseconds: baseline.targetMilliseconds
        )
    )
}

func median(of values: [Double]) -> Double {
    let sorted = values.sorted()
    let middleIndex = sorted.count / 2
    guard sorted.count.isMultiple(of: 2) else {
        return sorted[middleIndex]
    }
    return (sorted[middleIndex - 1] + sorted[middleIndex]) / 2
}

func trialColumnNames(count: Int) -> String {
    (1 ... count).map { "Trial \($0)" }.joined(separator: " | ")
}

func trialColumnSeparators(count: Int) -> String {
    Array(repeating: "---:", count: count).joined(separator: " | ")
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
