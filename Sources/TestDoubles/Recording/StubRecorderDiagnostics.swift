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
                lines.append(contentsOf: nearMissBreakdown(entry: entry, args: args))
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

    /// Shows, per argument, which matcher of a registered stub accepted or
    /// rejected the actual call, so the closest near-miss is visible.
    ///
    /// Emitted only when the registration's matcher count matches the call's
    /// argument count. A count mismatch (an empty catch-all, which would not
    /// have reached a "no matching stub" failure, or an inconsistent
    /// requirement) gets a single explanatory line instead.
    private static func nearMissBreakdown(
        entry: StubRecorder.StubEntry,
        args: [Any]
    ) -> [String] {
        let matchers = entry.matchers
        guard matchers.isEmpty == false else { return [] }
        guard matchers.count == args.count else {
            return ["    expects \(matchers.count) argument(s), call had \(args.count)"]
        }
        return zip(args, matchers).enumerated().map { index, pair in
            let (arg, matcher) = pair
            if matcher.matches(value: arg) {
                return "    arg\(index) matched: \(matcher.diagnosticDescription)"
            }
            return "    arg\(index) rejected: expected \(matcher.diagnosticDescription), "
                + "got \(String(reflecting: arg))"
        }
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

    /// Renders every recorded invocation as an ordered, human-readable log,
    /// one call per line, for debugging a failing verification. Arguments are
    /// woven back into the requirement's labels, so a call reads the way it was
    /// written at the call site.
    static func interactionLog(_ calls: [RecordedCall]) -> String {
        guard calls.isEmpty == false else {
            return "[TestDoubles] No interactions recorded."
        }
        let numberWidth = String(calls.count).count
        let lines = calls.enumerated().map { index, call -> String in
            let number = String(index + 1)
            let padding = String(repeating: " ", count: numberWidth - number.count)
            let rendered = call.args.map { String(reflecting: $0) }
            return "  \(padding)#\(number)  \(weaveArguments(rendered, intoName: call.name))"
        }
        let noun = calls.count == 1 ? "interaction" : "interactions"
        return (["[TestDoubles] Recorded \(calls.count) \(noun) in order:"] + lines)
            .joined(separator: "\n")
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
        return weaveArguments(matchers, intoName: name)
    }

    /// Weaves already-rendered argument expressions back into a selector-style
    /// method name, producing `base(label: value, ...)`. Falls back to
    /// positional `name(value, ...)` when the name is not a labeled selector or
    /// its label count does not line up with the arguments, and returns the
    /// bare name when there are no arguments (a getter or a nullary call).
    static func weaveArguments(_ rendered: [String], intoName name: String) -> String {
        guard rendered.isEmpty == false else { return name }
        guard let open = name.firstIndex(of: "("),
            name.last == ")"
        else {
            return "\(name)(\(rendered.joined(separator: ", ")))"
        }

        let base = String(name[..<open])
        let labelText = name[name.index(after: open) ..< name.index(before: name.endIndex)]
        let labels =
            labelText
            .split(separator: ":", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init)
        guard labels.count == rendered.count else {
            return "\(base)(\(rendered.joined(separator: ", ")))"
        }

        let arguments = zip(labels, rendered).map { label, value in
            label == "_" ? value : "\(label): \(value)"
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
