import Foundation

/// Requirements and constraints a protocol inherits from protocols it refines.
extension ManualStubGenerator {
    /// Protocols this generator can see, keyed by name: its own source's
    /// declarations take precedence over those supplied by a batch.
    var visibleProtocols: [String: SwiftProtocolDeclaration] {
        knownProtocols.merging(
            SwiftProtocolDeclarationScanner(source: source).declarations().map { ($0.name, $0) },
            uniquingKeysWith: { _, local in local }
        )
    }

    /// `declaration` followed by every protocol it refines that this
    /// generator can see, each visited once.
    func refinementChain(of declaration: SwiftProtocolDeclaration) -> [SwiftProtocolDeclaration] {
        let visible = visibleProtocols
        var visited: Set<String> = []
        var chain = [SwiftProtocolDeclaration]()
        var pending = [declaration]
        while pending.isEmpty == false {
            let next = pending.removeFirst()
            guard visited.insert(next.name).inserted else { continue }
            chain.append(next)
            pending += next.inheritedTypeNames.compactMap { visible[$0] }
        }
        return chain
    }

    /// The protocol's own requirements followed by those it inherits from
    /// refined protocols, without duplicates.
    func inheritedRequirements(of declaration: SwiftProtocolDeclaration) -> [String] {
        var seen: Set<String> = []
        return refinementChain(of: declaration)
            .flatMap(\.body.requirements)
            .filter { seen.insert($0).inserted }
    }

    /// Whether the protocol, or a protocol it refines, restricts conformers
    /// to classes.
    func isClassBound(_ declaration: SwiftProtocolDeclaration) -> Bool {
        refinementChain(of: declaration).contains(where: \.isClassBound)
    }
}
