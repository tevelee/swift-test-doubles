import Foundation

/// An `associatedtype` requirement, which becomes a generic parameter of the
/// generated conformer.
struct AssociatedTypeDeclaration {
    let name: String
    let constraint: String?

    init?(_ requirement: String) {
        guard requirement.hasPrefix("associatedtype ") else { return nil }
        var remainder = requirement.dropFirst("associatedtype ".count)
        // A default type is a hint for conformers; the generic parameter
        // stays open.
        if let equals = remainder.firstIndex(of: "=") {
            remainder = remainder[..<equals]
        }
        let parts = remainder.split(separator: ":", maxSplits: 1)
        guard let name = parts.first?.trimmingCharacters(in: .whitespaces),
            name.isEmpty == false
        else { return nil }
        self.name = name
        let constraint = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        self.constraint = constraint.isEmpty ? nil : constraint
    }

    var genericParameter: String {
        constraint.map { "\(name): \($0)" } ?? name
    }
}

/// How the generated conformer is declared for a protocol's shape.
struct ConformerShape {
    let protocolName: String
    let declaration: SwiftProtocolDeclaration
    let associatedTypes: [AssociatedTypeDeclaration]
    let isClassBound: Bool

    var conformerName: String { "\(protocolName)StubConformer" }

    var isGeneric: Bool { associatedTypes.isEmpty == false }

    /// `<Key: Hashable, Value>`, or empty for a protocol without associated types.
    var genericParameters: String {
        isGeneric ? "<\(associatedTypes.map(\.genericParameter).joined(separator: ", "))>" : ""
    }

    /// The conformer's type spelled with its generic arguments.
    var conformerType: String {
        isGeneric
            ? "\(conformerName)<\(associatedTypes.map(\.name).joined(separator: ", "))>"
            : conformerName
    }

    /// The existential the conformer erases to. Primary associated types are
    /// bound to the conformer's generic parameters.
    var existential: String {
        let primary = declaration.primaryAssociatedTypeNames
        return primary.isEmpty
            ? "any \(protocolName)"
            : "any \(protocolName)<\(primary.joined(separator: ", "))>"
    }

    /// The type keyword and any isolation modifier.
    ///
    /// A type conforming to a global-actor protocol would otherwise infer that
    /// isolation for all of its members, including the nonisolated
    /// `AutomaticStubConformer` requirements. `nonisolated` keeps the type
    /// itself unisolated while each forwarded witness keeps the protocol's
    /// actor.
    var declarationPrefix: String {
        if declaration.inheritsActor { return "actor" }
        let kind = isClassBound ? "final class" : "struct"
        return declaration.globalActor == nil ? kind : "nonisolated \(kind)"
    }

    /// The stored stub, plus an explicit initializer where memberwise
    /// initialization is unavailable.
    var storedStubMembers: String {
        if declaration.inheritsActor || isClassBound {
            return "let stub: CompiledStub<\(conformerType)>\n\n"
                + "    init(stub: CompiledStub<\(conformerType)>) { self.stub = stub }"
        }
        return "let stub: CompiledStub<Self>"
    }

    /// Applies the protocol's global actor to a forwarded witness that does
    /// not declare its own isolation.
    func isolating(_ member: String, requirement: String) -> String {
        guard let actor = declaration.globalActor, declaration.inheritsActor == false else {
            return member
        }
        let words = requirement.split(whereSeparator: \.isWhitespace)
        let declaresIsolation = words.contains {
            $0 == "nonisolated" || ($0.hasPrefix("@") && $0.hasSuffix("Actor"))
        }
        return declaresIsolation ? member : "@\(actor) \(member)"
    }
}
