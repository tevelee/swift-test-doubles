import Foundation

@main
enum TestDoublesBenchmarks {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "compare" {
                let options = try CompareOptions.parse(Array(arguments.dropFirst()))
                try compareBenchmarks(options: options)
            } else {
                let options = try RunOptions.parse(arguments)
                _ = try await runBenchmarks(
                    benchmarkDefinitions(),
                    options: options
                )
            }
        } catch {
            FileHandle.standardError.write(
                Data("error: \(error)\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
