import CTestDoublesTrampoline
import Echo
import Foundation

final class ReabstractionThunkRegistry: @unchecked Sendable {
    static let shared = ReabstractionThunkRegistry()

    private let lock = NSLock()
    private var directToGenericThunks: [DirectToGenericThunk] = []
    private var genericToDirectThunks: [DirectToGenericThunk] = []
    private var directAddresses: Set<UInt> = []
    private var genericAddresses: Set<UInt> = []

    private init() {
        refresh()
    }

    func directToGeneric(for metadata: FunctionMetadata) -> UnsafeRawPointer? {
        lookup(in: directToGenericSnapshot(), metadata: metadata)
            ?? refreshedLookup(in: directToGenericSnapshot, metadata: metadata)
    }

    func genericToDirect(for metadata: FunctionMetadata) -> UnsafeRawPointer? {
        lookup(in: genericToDirectSnapshot(), metadata: metadata)
            ?? refreshedLookup(in: genericToDirectSnapshot, metadata: metadata)
    }

    func hasBothDirections(for metadata: FunctionMetadata) -> Bool {
        directToGeneric(for: metadata) != nil && genericToDirect(for: metadata) != nil
    }

    private func lookup(
        in thunks: [DirectToGenericThunk],
        metadata: FunctionMetadata
    ) -> UnsafeRawPointer? {
        thunks.first {
            $0.thunk.isAsyncDescriptor == functionIsAsync(metadata)
                && FunctionSignatureMatcher.direct(
                    $0.directSignature,
                    matches: metadata
                )
                && FunctionSignatureMatcher.generic(
                    $0.genericSignature,
                    matches: metadata
                )
        }?.thunk.address
    }

    private func refreshedLookup(
        in snapshot: () -> [DirectToGenericThunk],
        metadata: FunctionMetadata
    ) -> UnsafeRawPointer? {
        refresh()
        return lookup(in: snapshot(), metadata: metadata)
    }

    private func refresh() {
        let collector = ReabstractionThunkCollector()
        td_visit_local_symbols(
            collectReabstractionThunk,
            Unmanaged.passUnretained(collector).toOpaque()
        )
        let direct = collector.thunksByDemangledName.flatMap { name, thunks in
            guard let pair = reabstractionPair(in: name), pair.sourceIsGeneric == false else {
                return [DirectToGenericThunk]()
            }
            return thunks.map {
                DirectToGenericThunk(
                    directSignature: pair.source,
                    genericSignature: pair.target,
                    thunk: $0
                )
            }
        }
        let generic = collector.thunksByDemangledName.flatMap { name, thunks in
            guard let pair = reabstractionPair(in: name), pair.sourceIsGeneric else {
                return [DirectToGenericThunk]()
            }
            return thunks.map {
                DirectToGenericThunk(
                    directSignature: pair.target,
                    genericSignature: pair.source,
                    thunk: $0
                )
            }
        }
        lock.lock()
        for thunk in direct {
            let address = UInt(bitPattern: thunk.thunk.address)
            if directAddresses.insert(address).inserted {
                directToGenericThunks.append(thunk)
            }
        }
        for thunk in generic {
            let address = UInt(bitPattern: thunk.thunk.address)
            if genericAddresses.insert(address).inserted {
                genericToDirectThunks.append(thunk)
            }
        }
        lock.unlock()
    }

    private func directToGenericSnapshot() -> [DirectToGenericThunk] {
        lock.lock()
        defer { lock.unlock() }
        return directToGenericThunks
    }

    private func genericToDirectSnapshot() -> [DirectToGenericThunk] {
        lock.lock()
        defer { lock.unlock() }
        return genericToDirectThunks
    }
}

private struct ReabstractionThunk {
    let address: UnsafeRawPointer
    let isAsyncDescriptor: Bool
}

private struct DirectToGenericThunk {
    let directSignature: LoweredFunctionSyntax
    let genericSignature: LoweredFunctionSyntax
    let thunk: ReabstractionThunk
}

private final class ReabstractionThunkCollector {
    var thunksByDemangledName: [String: [ReabstractionThunk]] = [:]
}

private let collectReabstractionThunk:
    @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeRawPointer?,
        UnsafeMutableRawPointer?
    ) -> Bool = { name, address, context in
        guard let name, let address, let context else { return true }
        let mangledName = String(cString: name)
        guard mangledName.hasSuffix("TQ0_") == false else { return true }
        let collector = Unmanaged<ReabstractionThunkCollector>
            .fromOpaque(context)
            .takeUnretainedValue()
        let demangled = normalizedThunkName(
            demangleReabstractionSymbol(mangledName)
        )
        collector.thunksByDemangledName[demangled, default: []].append(
            ReabstractionThunk(
                address: address,
                isAsyncDescriptor: mangledName.hasSuffix("Tu")
            )
        )
        return true
    }

private struct ReabstractionPair {
    let sourceIsGeneric: Bool
    let source: LoweredFunctionSyntax
    let target: LoweredFunctionSyntax
}

private let reabstractionPrefix =
    "partial apply forwarder for reabstraction thunk helper from "

private func reabstractionPair(in demangled: String) -> ReabstractionPair? {
    guard demangled.hasPrefix(reabstractionPrefix) else { return nil }
    let body = demangled.dropFirst(reabstractionPrefix.count)
    guard let separator = body.range(of: " to ", options: .backwards) else { return nil }
    guard let source = LoweredFunctionSyntax(String(body[..<separator.lowerBound])),
        let target = LoweredFunctionSyntax(String(body[separator.upperBound...]))
    else {
        return nil
    }
    let sourceIsGeneric = source.isGeneric
    guard sourceIsGeneric != target.isGeneric else { return nil }
    return ReabstractionPair(
        sourceIsGeneric: sourceIsGeneric,
        source: source,
        target: target
    )
}
