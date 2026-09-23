import Foundation

/// Method forwarding, including deferred, borrowed, and rethrowing arguments.
extension ManualStubGenerator {
    func functionForwarder(_ requirement: String) throws -> String? {
        guard let funcRange = requirement.range(of: "func ") else { return nil }
        let receiver = "stub"
        guard let opening = requirement[funcRange.upperBound...].firstIndex(of: "(") else {
            return nil
        }
        guard let closing = matchingParen(in: requirement, opening: opening) else {
            return nil
        }
        let suffix = String(requirement[closing...])
        let effects = effects(in: suffix)
        let parameters = forwardedParameters(String(requirement[opening ... closing]))
        let borrowed = parameters.filter { $0.borrowedClosure != nil }
        if borrowed.contains(where: { $0.borrowedClosure?.globalActor != nil }) {
            throw unsupported(
                requirement,
                because: "a nonescaping closure parameter isolated to a global actor cannot be lent to the stub"
            )
        }
        let isRethrowing = effects.split(whereSeparator: \.isWhitespace).contains("rethrows")
        let rethrowsOnlyFromAutoclosures =
            isRethrowing && borrowed.isEmpty
            && parameters.contains { $0.autoclosure?.isThrowing == true }
        if isRethrowing, borrowed.isEmpty, rethrowsOnlyFromAutoclosures == false {
            throw unsupported(
                requirement,
                because: "a rethrows requirement needs a nonescaping closure parameter to rethrow from"
            )
        }
        let arguments = parameters.enumerated().map { index, parameter in
            forwardedArgument(parameter, at: index)
        }
        // Only the autoclosure can throw, so the forwarded call itself must
        // not: a configured error could reach a caller that passed a
        // nonthrowing expression.
        var invocation = forwardingInvocation(
            receiver: receiver,
            arguments: arguments,
            effects: rethrowsOnlyFromAutoclosures
                ? effects.replacingOccurrences(of: "rethrows", with: "")
                : effects
        )
        guard borrowed.isEmpty == false else {
            return "\(requirement) { \(invocation) }"
        }

        let isAsync = effects.contains("async")
        let isThrowing = effects.contains("throws")
        if isRethrowing {
            let borrows = borrowed.map { "\($0.local)Borrow" }.joined(separator: ", ")
            let prefix = isAsync ? "try await" : "try"
            invocation =
                "\(prefix) \(receiver).rethrowingCall(borrowing: \(borrows)) { \(invocation) }"
        }
        var lines = borrowed.flatMap { parameter in
            [
                "let \(parameter.local)Borrow = BorrowedClosure(\(parameter.local), parameter: \"\(parameter.local)\")",
                "defer { \(parameter.local)Borrow.end() }"
            ]
        }
        lines += borrowed.map { parameter in
            "let \(parameter.local)Proxy = \(proxyClosure(for: parameter))"
        }
        lines.append("return \(invocation)")
        var body = lines.joined(separator: "; ")
        let effectPrefix = [isThrowing ? "try" : nil, isAsync ? "await" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        let typedFailure = typedFailureType(in: effects).map { " throws(\($0))" } ?? ""
        for parameter in borrowed.reversed() {
            let call = "withoutActuallyEscaping(\(parameter.local)) { \(parameter.local)\(typedFailure) in \(body) }"
            body = effectPrefix.isEmpty ? call : "\(effectPrefix) \(call)"
            if parameter.local != borrowed.first?.local {
                body = "return \(body)"
            }
        }
        return "\(requirement) { \(body) }"
    }

    /// One forwarded parameter and how its argument reaches the stub.
    private struct ForwardedParameter {
        let local: String
        let isInout: Bool
        /// A nonescaping `@autoclosure`, evaluated for forwarding.
        let autoclosure: FunctionTypeSyntax?
        /// A nonescaping closure, lent to the stub for the call.
        let borrowedClosure: FunctionTypeSyntax?
    }

    private func forwardedParameters(_ parameters: String) -> [ForwardedParameter] {
        let body = String(parameters.dropFirst().dropLast())
        return splitTopLevel(body, on: ",").compactMap { parameter in
            let declaration = parameter.trimmingCharacters(in: .whitespaces)
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let names = declaration[..<colon].split(whereSeparator: \.isWhitespace).map(
                String.init
            )
            guard let local = names.last else { return nil }
            let type =
                declaration[declaration.index(after: colon)...]
                .components(separatedBy: " = ").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let function = FunctionTypeSyntax(type)
            let escapes = function?.attributes.contains("@escaping") ?? true
            let isAutoclosure = function?.attributes.contains("@autoclosure") ?? false
            return ForwardedParameter(
                local: local,
                isInout: type.hasPrefix("inout "),
                autoclosure: isAutoclosure && escapes == false ? function : nil,
                borrowedClosure: isAutoclosure == false && escapes == false ? function : nil
            )
        }
    }

    private func forwardedArgument(_ parameter: ForwardedParameter, at position: Int) -> String {
        if let autoclosure = parameter.autoclosure {
            let method = autoclosure.isAsync ? "deferredAsyncArgument" : "deferredArgument"
            let prefix = [autoclosure.isThrowing ? "try" : nil, autoclosure.isAsync ? "await" : nil]
                .compactMap { $0 }
                .joined(separator: " ")
            let call = "stub.\(method)(at: \(position), \(parameter.local))"
            return prefix.isEmpty ? call : "\(prefix) \(call)"
        }
        if parameter.borrowedClosure != nil {
            return "\(parameter.local)Proxy"
        }
        return parameter.isInout ? "&\(parameter.local)" : parameter.local
    }

    /// An escaping closure with the parameter's signature that calls through
    /// its borrow.
    private func proxyClosure(for parameter: ForwardedParameter) -> String {
        guard let function = parameter.borrowedClosure else { return parameter.local }
        let names = function.parameters.indices.map { "p\($0)" }
        let declarations = zip(names, function.parameters).map { "\($0): \($1)" }
            .joined(separator: ", ")
        let arguments = zip(names, function.parameters).map { name, type in
            type.hasPrefix("inout ") ? "&\(name)" : name
        }.joined(separator: ", ")
        let effects = [function.isAsync ? "async" : nil, function.throwsClause]
            .compactMap { $0 }
            .joined(separator: " ")
        let effectSuffix = effects.isEmpty ? "" : " \(effects)"
        let callPrefix = [function.isThrowing ? "try" : nil, function.isAsync ? "await" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        let invoke = callPrefix.isEmpty ? "function(\(arguments))" : "\(callPrefix) function(\(arguments))"
        let borrow =
            callPrefix.isEmpty
            ? "\(parameter.local)Borrow { (function)\(effectSuffix) -> \(function.result) in \(invoke) }"
            : "\(callPrefix) \(parameter.local)Borrow { (function)\(effectSuffix) -> \(function.result) in \(invoke) }"
        let attributes = function.attributes.filter { $0 == "@Sendable" }
        let attributePrefix = attributes.isEmpty ? "" : attributes.joined(separator: " ") + " "
        return "{ \(attributePrefix)(\(declarations))\(effectSuffix) -> \(function.result) in \(borrow) }"
    }
}
