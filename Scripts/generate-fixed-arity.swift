#!/usr/bin/env swift

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

private let maximumArity = 6
private let scriptName = "Scripts/generate-fixed-arity.swift"

private struct GeneratedFile {
    let path: String
    let contents: String
}

private enum GenerationMode {
    case write
    case check
}

private func typeParameters(for arity: Int) -> [String] {
    (0 ..< arity).map { "P\($0)" }
}

private func valueArguments(for arity: Int) -> String {
    "[" + (0 ..< arity).map { "$\($0)" }.joined(separator: ", ") + "]"
}

private func typeArguments(for arity: Int) -> String {
    (0 ..< arity).map { "                P\($0).self" }.joined(separator: ",\n")
}

private func closureParameters(for arity: Int) -> String {
    "(" + typeParameters(for: arity).joined(separator: ", ") + ")"
}

private func genericParameters(for arity: Int, suffix: [String]) -> String {
    (typeParameters(for: arity) + suffix).joined(separator: ", ")
}

private func typeOpeningBody(
    arity: Int,
    level: Int,
    indentation: String
) -> String {
    if level == arity {
        let openedTypes = (0 ..< arity).map { "type\($0)" }.joined(separator: ", ")
        let typeLines = arity == 0 ? "" : ",\n\(indentation)    \(openedTypes)"
        return """
            \(indentation)return boxDynamicFunction\(arity)(
            \(indentation)    invocation,
            \(indentation)    resultType: resultType,
            \(indentation)    isSendable: isSendable,
            \(indentation)    isThrowing: isThrowing,
            \(indentation)    isAsync: isAsync\(typeLines)
            \(indentation))
            """
    }

    let functionName = "openParameter\(level)"
    let typeName = "P\(level)"
    let valueName = "type\(level)"
    let inner = typeOpeningBody(
        arity: arity,
        level: level + 1,
        indentation: indentation + "    "
    )
    return """
        \(indentation)func \(functionName)<\(typeName)>(_ \(valueName): \(typeName).Type) -> Any {
        \(inner)
        \(indentation)}
        \(indentation)return _openExistential(
        \(indentation)    invocation.parameterTypes[\(level)],
        \(indentation)    do: \(functionName)
        \(indentation))
        """
}

private func dynamicDispatcher() -> String {
    let cases = (0 ... maximumArity).map { arity in
        if arity == 0 {
            return """
                    case 0:
                        return boxDynamicFunction0(
                            invocation,
                            resultType: resultType,
                            isSendable: isSendable,
                            isThrowing: isThrowing,
                            isAsync: isAsync
                        )
                """
        }
        return """
                case \(arity):
            \(typeOpeningBody(arity: arity, level: 0, indentation: "        "))
            """
    }.joined(separator: "\n")

    return """
        func dynamicallyBoxFunctionArgument(
            function: UnsafeRawPointer,
            context: UnsafeRawPointer?,
            plan: FunctionBridgePlan,
            discriminator: UInt16
        ) -> Any {
            // Opening six independently discovered parameter types requires one local
            // generic function per level. The nesting mirrors Swift's existential-open
            // operation and is bounded by the documented arity limit.
            // swiftlint:disable nesting
            let invocation = DynamicFunctionInvocation(
                function: function,
                context: context,
                discriminator: discriminator,
                plan: plan
            )
            let metadata = plan.metadata
            let isSendable = metadata.flags.bits & 0x4000_0000 != 0
            let isThrowing = plan.isThrowing
            let isAsync = plan.isAsync

            func boxResult<Result>(_ resultType: Result.Type) -> Any {
                switch invocation.parameterTypes.count {
        \(cases.indented(by: 8))
                    default:
                        preconditionFailure(
                            "[TestDoubles] Dynamic function arity changed after validation."
                        )
                }
            }
            return _openExistential(metadata.resultType, do: boxResult)
            // swiftlint:enable nesting
        }
        """
}

private struct UntypedClosureVariant {
    let condition: String?
    let sendable: Bool
    let effects: String
    let call: String
}

private let untypedClosureVariants: [UntypedClosureVariant] = [
    .init(
        condition: "isAsync, isThrowing, isSendable",
        sendable: true,
        effects: "async throws",
        call: "try await invocation.callAsyncThrowing"
    ),
    .init(
        condition: "isAsync, isThrowing",
        sendable: false,
        effects: "async throws",
        call: "try await invocation.callAsyncThrowing"
    ),
    .init(
        condition: "isAsync, isSendable",
        sendable: true,
        effects: "async",
        call: "await invocation.callAsync"
    ),
    .init(
        condition: "isAsync",
        sendable: false,
        effects: "async",
        call: "await invocation.callAsync"
    ),
    .init(
        condition: "isThrowing, isSendable",
        sendable: true,
        effects: "throws",
        call: "try invocation.callThrowing"
    ),
    .init(
        condition: "isThrowing",
        sendable: false,
        effects: "throws",
        call: "try invocation.callThrowing"
    ),
    .init(
        condition: "isSendable",
        sendable: true,
        effects: "",
        call: "invocation.call"
    ),
    .init(
        condition: nil,
        sendable: false,
        effects: "",
        call: "invocation.call"
    )
]

private func functionType(
    arity: Int,
    sendable: Bool,
    effects: String,
    typedFailure: Bool
) -> String {
    let prefix = sendable ? "@Sendable " : ""
    let renderedEffects =
        typedFailure
        ? [effects, "throws(Failure)"].filter { $0.isEmpty == false }.joined(separator: " ")
        : effects
    let effectSuffix = renderedEffects.isEmpty ? "" : " \(renderedEffects)"
    return "\(prefix)\(closureParameters(for: arity))\(effectSuffix) -> Result"
}

private func untypedClosureCase(
    arity: Int,
    variant: UntypedClosureVariant
) -> String {
    let condition = variant.condition.map { "if \($0) {\n" } ?? ""
    let indentation = variant.condition == nil ? "" : "    "
    let closing = variant.condition == nil ? "" : "\n}"
    return """
        \(condition)\(indentation)let closure: \(functionType(
        arity: arity,
        sendable: variant.sendable,
        effects: variant.effects,
        typedFailure: false
        )) = {
        \(indentation)    \(variant.call)(
        \(indentation)        \(valueArguments(for: arity)),
        \(indentation)        returning: resultType
        \(indentation)    )
        \(indentation)}
        \(indentation)return closure\(closing)
        """
}

private func dynamicBoxFunction(arity: Int) -> String {
    let generic = genericParameters(for: arity, suffix: ["Result"])
    let parameterTypes = typeParameters(for: arity).map { type in
        "    _: \(type).Type"
    }.joined(separator: ",\n")
    let parameterSuffix = parameterTypes.isEmpty ? "" : ",\n\(parameterTypes)"
    let openedTypes = typeArguments(for: arity)
    let openedTypeSuffix = openedTypes.isEmpty ? "" : ",\n\(openedTypes)"
    let cases = untypedClosureVariants.map {
        untypedClosureCase(arity: arity, variant: $0)
    }.joined(separator: "\n")

    return """
        private func boxDynamicFunction\(arity)<\(generic)>(
            _ invocation: DynamicFunctionInvocation,
            resultType: Result.Type,
            isSendable: Bool,
            isThrowing: Bool,
            isAsync: Bool\(parameterSuffix)
        ) -> Any {
            if let errorType = invocation.typedErrorType {
                guard #available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *) else {
                    preconditionFailure(
                        "[TestDoubles] Typed closure runtime support is unavailable on this OS version."
                    )
                }
                func openFailure<Failure: Error>(_ failureType: Failure.Type) -> Any {
                    boxDynamicTypedFunction\(arity)(
                        invocation,
                        failureType: failureType,
                        resultType: resultType,
                        isSendable: isSendable,
                        isAsync: isAsync\(openedTypeSuffix)
                    )
                }
                return _openExistential(errorType, do: openFailure)
            }
        \(cases.indented(by: 4))
        }
        """
}

private struct TypedClosureVariant {
    let condition: String?
    let sendable: Bool
    let isAsync: Bool
}

private let typedClosureVariants: [TypedClosureVariant] = [
    .init(condition: "isAsync, isSendable", sendable: true, isAsync: true),
    .init(condition: "isAsync", sendable: false, isAsync: true),
    .init(condition: "isSendable", sendable: true, isAsync: false),
    .init(condition: nil, sendable: false, isAsync: false)
]

private func typedClosureCase(
    arity: Int,
    variant: TypedClosureVariant
) -> String {
    let condition = variant.condition.map { "if \($0) {\n" } ?? ""
    let indentation = variant.condition == nil ? "" : "    "
    let closing = variant.condition == nil ? "" : "\n}"
    let call =
        variant.isAsync
        ? "try await invocation.callAsyncTyped"
        : "try invocation.callTyped"
    let effects = variant.isAsync ? "async" : ""
    return """
        \(condition)\(indentation)let closure: \(functionType(
        arity: arity,
        sendable: variant.sendable,
        effects: effects,
        typedFailure: true
        )) = {
        \(indentation)    \(call)(
        \(indentation)        \(valueArguments(for: arity)),
        \(indentation)        throwing: failureType,
        \(indentation)        returning: resultType
        \(indentation)    )
        \(indentation)}
        \(indentation)return closure\(closing)
        """
}

private func dynamicTypedBoxFunction(arity: Int) -> String {
    let generic = genericParameters(
        for: arity,
        suffix: ["Failure: Error", "Result"]
    )
    let parameterTypes = typeParameters(for: arity).map {
        "    _: \($0).Type"
    }.joined(separator: ",\n")
    let parameterSuffix = parameterTypes.isEmpty ? "" : ",\n\(parameterTypes)"
    let cases = typedClosureVariants.map {
        typedClosureCase(arity: arity, variant: $0)
    }.joined(separator: "\n")

    return """
        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
        private func boxDynamicTypedFunction\(arity)<\(generic)>(
            _ invocation: DynamicFunctionInvocation,
            failureType: Failure.Type,
            resultType: Result.Type,
            isSendable: Bool,
            isAsync: Bool\(parameterSuffix)
        ) -> Any {
        \(cases.indented(by: 4))
        }
        """
}

extension String {
    fileprivate func indented(by count: Int) -> String {
        let indentation = String(repeating: " ", count: count)
        return split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : indentation + $0 }
            .joined(separator: "\n")
    }
}

private func dynamicBoxingSource() -> String {
    let untyped = (0 ... maximumArity)
        .map(dynamicBoxFunction)
        .joined(separator: "\n\n")
    let typed = (0 ... maximumArity)
        .map(dynamicTypedBoxFunction)
        .joined(separator: "\n\n")
    return """
        // Generated by \(scriptName); do not edit by hand.
        // Fixed concrete arities are required because Swift cannot reliably erase a
        // variadic function type to Any.
        // swiftlint:disable file_length

        import Echo

        \(dynamicDispatcher())

        \(untyped)

        \(typed)

        // swiftlint:enable file_length
        """ + "\n"
}

private enum MethodEffectVariant {
    case synchronous
    case synchronousThrowing
    case asynchronous
    case asynchronousThrowing

    var documentationAdjective: String {
        switch self {
            case .synchronous: "synchronous"
            case .synchronousThrowing: "synchronous throwing"
            case .asynchronous: "asynchronous"
            case .asynchronousThrowing: "asynchronous throwing"
        }
    }

    var genericFailure: Bool {
        switch self {
            case .synchronous, .asynchronous: false
            case .synchronousThrowing, .asynchronousThrowing: true
        }
    }

    var functionEffects: String {
        switch self {
            case .synchronous: ""
            case .synchronousThrowing: " throws(Failure)"
            case .asynchronous: " async"
            case .asynchronousThrowing: " async throws(Failure)"
        }
    }

    var isAsync: Bool {
        switch self {
            case .synchronous, .synchronousThrowing: false
            case .asynchronous, .asynchronousThrowing: true
        }
    }
}

private let arityWords = ["zero", "one", "two", "three", "four", "five", "six"]

private func signatureOfMethod(
    arity: Int,
    effect: MethodEffectVariant
) -> String {
    let arguments = typeParameters(for: arity).map { $0.replacingOccurrences(of: "P", with: "A") }
    let generic = (arguments + ["Result"] + (effect.genericFailure ? ["Failure: Error"] : []))
        .joined(separator: ", ")
    let functionArguments = "(" + arguments.joined(separator: ", ") + ")"
    let inferredArguments = "[" + arguments.map { "\($0).self" }.joined(separator: ", ") + "]"
    let article = effect.isAsync ? "an" : "a"
    var lines = [
        "    /// Infers \(article) \(effect.documentationAdjective) \(arityWords[arity])-argument method requirement from a protocol method reference.",
        "    public static func method<\(generic)>(",
        "        signatureOf method: (_ instance: P) -> \(functionArguments)\(effect.functionEffects) -> Result",
        "    ) -> Self {",
        "        _ = method"
    ]
    if effect.genericFailure {
        lines.append("        let effect = inferredThrowingEffect(for: Failure.self)")
    }
    lines.append(contentsOf: [
        "        return inferredMethod(",
        "            arguments: \(inferredArguments),",
        "            returning: Result.self,"
    ])
    if effect.genericFailure {
        lines.append(contentsOf: [
            "            typedErrorType: effect.typedErrorType,",
            "            isThrowing: effect.isThrowing,"
        ])
    } else {
        lines.append("            isThrowing: false,")
    }
    lines.append(contentsOf: [
        "            isAsync: \(effect.isAsync)",
        "        )",
        "    }"
    ])
    return lines.joined(separator: "\n")
}

private func signatureOfSource() -> String {
    let effects: [MethodEffectVariant] = [
        .synchronous,
        .synchronousThrowing,
        .asynchronous,
        .asynchronousThrowing
    ]
    let methods = (0 ... maximumArity).flatMap { arity in
        effects.map { signatureOfMethod(arity: arity, effect: $0) }
    }.joined(separator: "\n\n")
    return """
        // Generated by \(scriptName); do not edit by hand.
        // Swift cannot reabstract an unbound method reference through a parameter-pack
        // function parameter. Keep these convenience overloads at fixed arities; the
        // explicit metatype-based factory continues to support arbitrary arity.
        extension Stub.Requirement {
        \(methods)
        }
        """ + "\n"
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private let mode: GenerationMode = {
    switch Array(CommandLine.arguments.dropFirst()) {
        case []: return .write
        case ["--check"]: return .check
        default: fail("usage: \(scriptName) [--check]")
    }
}()

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let generatedFiles = [
    GeneratedFile(
        path: "Sources/TestDoubles/Runtime/DynamicFunctionBoxing+Generated.swift",
        contents: dynamicBoxingSource()
    ),
    GeneratedFile(
        path: "Sources/TestDoubles/Preparation/StubRequirement+SignatureOf.swift",
        contents: signatureOfSource()
    )
]

var staleFiles: [String] = []
for file in generatedFiles {
    let destination = root.appendingPathComponent(file.path)
    let expected = Data(file.contents.utf8)
    switch mode {
        case .write:
            do {
                try expected.write(to: destination, options: .atomic)
            } catch {
                fail("failed to write \(file.path): \(error)")
            }
        case .check:
            guard let actual = try? Data(contentsOf: destination), actual == expected else {
                staleFiles.append(file.path)
                continue
            }
    }
}

if staleFiles.isEmpty == false {
    fail(
        "Generated fixed-arity sources are stale:\n"
            + staleFiles.map { "  \($0)" }.joined(separator: "\n")
            + "\nRun: xcrun swift \(scriptName)"
    )
}

if mode == .check {
    print("Generated fixed-arity sources are current.")
}
