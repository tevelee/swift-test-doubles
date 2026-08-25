#!/usr/bin/env swift

import Foundation

private let outputPath =
    "Sources/TestDoubles/Runtime/Preparation/BuiltInResultAdapters+Generated.swift"

private enum GeneratorError: Error, CustomStringConvertible {
    case invalidArguments
    case formattingFailed
    case generatedFileIsOutOfDate

    var description: String {
        switch self {
            case .invalidArguments:
                "Usage: swift Scripts/generate-built-in-result-adapters.swift [--check]"
            case .formattingFailed:
                "swift-format failed while formatting built-in result adapters."
            case .generatedFileIsOutOfDate:
                "BuiltInResultAdapters+Generated.swift is out of date. Run Scripts/generate-built-in-result-adapters.swift."
        }
    }
}

private struct Entry {
    enum Transport: String {
        case direct
        case indirect
    }

    let functionSuffix: String
    let type: String
    let placeholder: String
    let transport: Transport
    let condition: String?

    init(
        _ functionSuffix: String,
        _ type: String,
        placeholder: String,
        transport: Transport,
        condition: String? = nil
    ) {
        self.functionSuffix = functionSuffix
        self.type = type
        self.placeholder = placeholder
        self.transport = transport
        self.condition = condition
    }
}

private let networkCondition =
    "canImport(Darwin) || (canImport(FoundationNetworking) && !os(Android))"

// Result transport is the compiler lowering of the concrete thin adapter, not
// a size-based runtime guess. BuiltInFoundationResultConsumerTests invokes every
// entry from an external module so a platform or toolchain drift fails the gate.
private let entries: [Entry] = [
    Entry("URL", "URL", placeholder: "URL(filePath: \"/test-doubles-placeholder\")", transport: .indirect),
    Entry("Data", "Data", placeholder: "Data([0x54, 0x44])", transport: .direct),
    Entry("Date", "Date", placeholder: "Date(timeIntervalSinceReferenceDate: 1)", transport: .indirect),
    Entry(
        "UUID",
        "UUID",
        placeholder: "UUID(uuidString: \"54455354-444F-5542-4C45-530000000001\")",
        transport: .indirect
    ),
    Entry("Calendar", "Calendar", placeholder: "Calendar(identifier: .gregorian)", transport: .indirect),
    Entry("Locale", "Locale", placeholder: "Locale(identifier: \"en_US_POSIX\")", transport: .indirect),
    Entry("TimeZone", "TimeZone", placeholder: "TimeZone(secondsFromGMT: 0)", transport: .indirect),
    Entry("IndexPath", "IndexPath", placeholder: "IndexPath(index: 0)", transport: .indirect),
    Entry("IndexSet", "IndexSet", placeholder: "IndexSet(integer: 0)", transport: .indirect),
    Entry(
        "DateInterval",
        "DateInterval",
        placeholder: "DateInterval(start: Date(timeIntervalSinceReferenceDate: 1), duration: 1)",
        transport: .indirect
    ),
    Entry(
        "CharacterSet",
        "CharacterSet",
        placeholder: "CharacterSet(charactersIn: \"A\")",
        transport: .indirect
    ),
    Entry("Decimal", "Decimal", placeholder: "Decimal(1)", transport: .direct),
    Entry(
        "NotificationName",
        "Notification.Name",
        placeholder: "Notification.Name(\"TestDoubles.Placeholder\")",
        transport: .direct
    ),
    Entry(
        "Notification",
        "Notification",
        placeholder: "Notification(name: Notification.Name(\"TestDoubles.Placeholder\"))",
        transport: .indirect
    ),
    Entry(
        "AttributedString",
        "AttributedString",
        placeholder: "AttributedString(\"test-doubles-placeholder\")",
        transport: .indirect
    ),
    Entry(
        "PersonNameComponents",
        "PersonNameComponents",
        placeholder: "personNameComponents()",
        transport: .indirect
    ),
    Entry(
        "URLRequest",
        "URLRequest",
        placeholder: "URLRequest(url: URL(filePath: \"/test-doubles-placeholder\"))",
        transport: .indirect,
        condition: networkCondition
    )
]

private func conditionallyWrap(_ text: String, condition: String?) -> String {
    guard let condition else { return text }
    return """
        #if \(condition)
        \(text)
        #endif
        """
}

private func placeholderCases() -> String {
    entries.map { entry in
        conditionallyWrap(
            "case is \(entry.type).Type:\n    \(entry.placeholder)",
            condition: entry.condition
        )
    }.joined(separator: "\n")
}

private func appendCalls() -> String {
    entries.map { entry in
        conditionallyWrap(
            "append\(entry.functionSuffix)(to: &adapters)",
            condition: entry.condition
        )
    }.joined(separator: "\n")
}

private func adapterFunction(for entry: Entry) -> String {
    let function = """
        private static func append\(entry.functionSuffix)(
            to adapters: inout [RuntimeAutomaticRequirementAdapter]
        ) {
            let synchronous:
                @convention(thin) (BuiltInResultInvocation) -> \(entry.type) =
                    { invocation in invocation.call(returning: \(entry.type).self) as! \(entry.type) }
            let synchronousThrowing:
                @convention(thin) (BuiltInResultInvocation) throws -> \(entry.type) =
                    { invocation in try invocation.callThrowing(returning: \(entry.type).self) as! \(entry.type) }
            let asynchronous:
                @convention(thin) (BuiltInResultInvocation) async -> \(entry.type) =
                    { invocation in await invocation.call() as! \(entry.type) }
            let asynchronousThrowing:
                @convention(thin) (BuiltInResultInvocation) async throws -> \(entry.type) =
                    { invocation in try await invocation.callThrowing() as! \(entry.type) }
            append(
                returning: \(entry.type).self,
                resultTransport: .\(entry.transport.rawValue),
                synchronous: token(for: synchronous),
                synchronousThrowing: token(for: synchronousThrowing),
                asynchronous: token(for: asynchronous),
                asynchronousThrowing: token(for: asynchronousThrowing),
                to: &adapters
            )
        }
        """
    return conditionallyWrap(function, condition: entry.condition)
}

private func generatedSource() -> String {
    let functions = entries.map(adapterFunction).joined(separator: "\n\n")
    return """
        // Generated by Scripts/generate-built-in-result-adapters.swift; do not edit by hand.

        import Foundation
        #if canImport(FoundationNetworking) && !os(Android)
            import FoundationNetworking
        #endif
        import InternalRuntimeContract

        // The catalog fixes the result type for each compiler-typed adapter.
        // swiftlint:disable force_cast

        enum BuiltInFoundationValueCatalog {
            static func placeholder(for type: Any.Type) -> Any? {
                switch type {
        \(placeholderCases().split(separator: "\n", omittingEmptySubsequences: false).map { "            " + $0 }.joined(separator: "\n"))
                    default:
                        nil
                }
            }

            private static func personNameComponents() -> PersonNameComponents {
                var components = PersonNameComponents()
                components.givenName = "Test"
                components.familyName = "Doubles"
                return components
            }
        }

        extension BuiltInResultAdapters {
            static func appendFoundationAdapters(
                to adapters: inout [RuntimeAutomaticRequirementAdapter]
            ) {
        \(appendCalls().split(separator: "\n", omittingEmptySubsequences: false).map { "        " + $0 }.joined(separator: "\n"))
            }

        \(functions.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n"))
        }
        // swiftlint:enable force_cast
        """ + "\n"
}

private func format(_ url: URL) throws {
    let formatter = Process()
    formatter.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    formatter.arguments = [
        "swift-format", "format", "--configuration", ".swift-format",
        "--in-place", url.path
    ]
    try formatter.run()
    formatter.waitUntilExit()
    guard formatter.terminationStatus == 0 else {
        throw GeneratorError.formattingFailed
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || arguments == ["--check"] else {
    throw GeneratorError.invalidArguments
}

let destination = URL(fileURLWithPath: outputPath)
let generated = generatedSource()

if arguments == ["--check"] {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
        "BuiltInResultAdapters-\(UUID().uuidString).swift"
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    try generated.write(to: temporary, atomically: true, encoding: .utf8)
    try format(temporary)
    let expected = try String(contentsOf: destination, encoding: .utf8)
    let actual = try String(contentsOf: temporary, encoding: .utf8)
    guard actual == expected else {
        throw GeneratorError.generatedFileIsOutOfDate
    }
} else {
    try generated.write(
        to: destination,
        atomically: true,
        encoding: .utf8
    )
    try format(destination)
}
