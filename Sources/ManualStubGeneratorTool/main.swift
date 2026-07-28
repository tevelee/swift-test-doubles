import Foundation
import ManualStubGeneratorCore

func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

guard CommandLine.arguments.count == 4 else {
    writeError("usage: ManualStubGeneratorTool <protocol-name> <input-swift-file> <output-swift-file>")
    exit(64)
}

let protocolName = CommandLine.arguments[1]
let inputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

do {
    let source = try String(contentsOf: inputURL, encoding: .utf8)
    let output = try ManualStubGenerator(protocolName: protocolName, source: source).render()
    try output.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    writeError("ManualStubGeneratorTool: \(error.localizedDescription)")
    exit(1)
}
