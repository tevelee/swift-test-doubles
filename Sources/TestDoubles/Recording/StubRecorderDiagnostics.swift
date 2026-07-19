enum StubRecorderDiagnostics {
    static func dispatchFailure(
        title: String,
        method: MethodDescriptor,
        args: [Any],
        entries: [StubRecorder.StubEntry]
    ) -> String {
        var lines: [String] = [
            "[TestDoubles] \(title) for \(method.name)",
            "",
            "Actual:"
        ]
        if args.isEmpty {
            lines.append("  <no arguments>")
        } else {
            for (index, arg) in args.enumerated() {
                lines.append("  arg\(index): \(String(reflecting: arg))")
            }
        }

        lines.append("")
        lines.append("Registered stubs:")
        if entries.isEmpty {
            lines.append("  <none>")
        } else {
            for entry in entries {
                lines.append("  \(entry.diagnosticSignature)")
            }
        }

        lines.append("")
        lines.append("Action:")
        if entries.isEmpty {
            lines.append(
                "  Register behavior with `stub.when { ... }` before invoking this requirement."
            )
        } else {
            lines.append(
                "  Add a `stub.when { ... }` registration whose matchers accept these arguments, "
                    + "or correct the call if the arguments are unexpected."
            )
        }

        if method.origin != .explicit {
            lines.append("")
            lines.append("Suggested:")
            lines.append("  \(suggestedStubSnippet(method: method, args: args))")
        }
        return lines.joined(separator: "\n")
    }

    static func orderedVerificationFailure(
        expectationIndex: Int,
        expectation: RecordedCall,
        calls: [RecordedCall]
    ) -> String {
        let expectedMatchers = expectation.resolvedMatchers
            .map(\.diagnosticDescription)
            .joined(separator: ", ")
        let location =
            expectationIndex == 0
            ? "in the recorded calls"
            : "after expectation \(expectationIndex)"
        var lines = [
            "Expected calls in order, but expectation \(expectationIndex + 1) was not found \(location).",
            "Expected: \(expectation.name)(\(expectedMatchers))",
            "Recorded call order:"
        ]
        if calls.isEmpty {
            lines.append("  <none>")
        } else {
            for call in calls {
                let arguments = call.args.map { String(reflecting: $0) }.joined(separator: ", ")
                lines.append("  \(call.name)(\(arguments))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func unverifiedInteractions(_ calls: [RecordedCall]) -> String? {
        guard calls.isEmpty == false else { return nil }

        let count = calls.count
        var lines = [
            "Expected no more interactions, but found \(count) unverified "
                + "\(count == 1 ? "interaction" : "interactions") in recorded order:"
        ]
        for (index, call) in calls.enumerated() {
            let arguments = call.args.map { String(reflecting: $0) }.joined(separator: ", ")
            lines.append("  \(index + 1)/\(count): \(call.name)(\(arguments))")
        }
        return lines.joined(separator: "\n")
    }

    private static func suggestedStubSnippet(
        method: MethodDescriptor,
        args: [Any]
    ) -> String {
        let invocation = suggestedInvocation(name: method.name, args: args)
        let configurationPrefix = method.isAsync ? "await " : ""
        let effectPrefix = [
            method.isThrowing ? "try" : nil,
            method.isAsync ? "await" : nil
        ].compactMap { $0 }.joined(separator: " ")
        func requirementCall(_ expression: String) -> String {
            effectPrefix.isEmpty ? expression : "\(effectPrefix) \(expression)"
        }

        if method.kind == .initializer {
            return "\(configurationPrefix)stub.when(initializer: { \(requirementCall("type(of: $0).\(invocation)")) }).thenInitialize()"
        }
        if method.returnConvention == .selfType {
            let receiver =
                switch method.receiver {
                    case .instance: "$0"
                    case .metatype: "type(of: $0)"
                }
            return
                "\(configurationPrefix)stub.when(returningSelf: { \(requirementCall("\(receiver).\(invocation)")) }).thenReturnValue()"
        }
        if method.returnConvention == .optionalSelf {
            let receiver =
                switch method.receiver {
                    case .instance: "$0"
                    case .metatype: "type(of: $0)"
                }
            return
                "\(configurationPrefix)stub.when(returningOptionalSelf: { \(requirementCall("\(receiver).\(invocation)")) }).thenReturnValue()"
        }
        let receiver =
            switch method.receiver {
                case .instance: "$0"
                case .metatype: "type(of: $0)"
            }
        let behavior =
            method.returnType == Void.self
            ? ".thenDoNothing()"
            : ".thenReturn(...)"
        return "\(configurationPrefix)stub.when { \(requirementCall("\(receiver).\(invocation)")) }\(behavior)"
    }

    private static func suggestedInvocation(name: String, args: [Any]) -> String {
        guard args.isEmpty == false else { return name }
        let matchers = args.map { "equal(\(swiftLiteralDescription($0)))" }

        guard let open = name.firstIndex(of: "("),
            name.last == ")"
        else {
            return "\(name)(\(matchers.joined(separator: ", ")))"
        }

        let base = String(name[..<open])
        let labelText = name[name.index(after: open) ..< name.index(before: name.endIndex)]
        let labels =
            labelText
            .split(separator: ":", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init)
        guard labels.count == matchers.count else {
            return "\(base)(\(matchers.joined(separator: ", ")))"
        }

        let arguments = zip(labels, matchers).map { label, matcher in
            label == "_" ? matcher : "\(label): \(matcher)"
        }.joined(separator: ", ")
        return "\(base)(\(arguments))"
    }

    private static func swiftLiteralDescription(_ value: Any) -> String {
        switch value {
            case let value as String:
                return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
            case let value as Character:
                return "\"\(value)\""
            default:
                return String(describing: value)
        }
    }
}

extension StubRecorder {
    /// Internal rather than private so the composed diagnostic can be tested
    /// directly; production callers surface it only through `fatalError`.
    func diagnosticMessage(
        title: String,
        method: MethodDescriptor,
        args: [Any],
        entries: [StubEntry]
    ) -> String {
        StubRecorderDiagnostics.dispatchFailure(
            title: title,
            method: method,
            args: args,
            entries: entries
        )
    }
}
