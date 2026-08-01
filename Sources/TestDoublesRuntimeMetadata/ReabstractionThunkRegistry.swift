import CTestDoublesTrampoline
import EchoRuntimeReflection
import Foundation
import TestDoublesRuntimeSupport

package final class ReabstractionThunkRegistry: @unchecked Sendable {
    package static let shared = ReabstractionThunkRegistry()

    private let lock = NSLock()
    private var directToGenericThunks: [DirectToGenericThunk] = []
    private var genericToDirectThunks: [DirectToGenericThunk] = []
    private var directAddresses: Set<UInt> = []
    private var genericAddresses: Set<UInt> = []
    private var refreshGeneration = 0

    private init() {
        refresh()
    }

    package func directToGeneric(for type: Any.Type) -> UnsafeRawPointer? {
        guard let function = FunctionTypeInfo(reflecting: type) else { return nil }
        let snapshot = directToGenericSnapshot()
        return lookup(in: snapshot.thunks, function: function)
            ?? refreshedLookup(
                in: directToGenericSnapshot,
                after: snapshot.generation,
                function: function
            )
    }

    package func genericToDirect(for type: Any.Type) -> UnsafeRawPointer? {
        guard let function = FunctionTypeInfo(reflecting: type) else { return nil }
        let snapshot = genericToDirectSnapshot()
        return lookup(in: snapshot.thunks, function: function)
            ?? refreshedLookup(
                in: genericToDirectSnapshot,
                after: snapshot.generation,
                function: function
            )
    }

    package func hasBothDirections(for type: Any.Type) -> Bool {
        directToGeneric(for: type) != nil && genericToDirect(for: type) != nil
    }

    private func lookup(
        in thunks: [DirectToGenericThunk],
        function: FunctionTypeInfo
    ) -> UnsafeRawPointer? {
        thunks.first {
            $0.thunk.isAsyncDescriptor == function.effects.isAsync
                && FunctionSignatureMatcher.direct(
                    $0.directSignature,
                    matches: function
                )
                && FunctionSignatureMatcher.generic(
                    $0.genericSignature,
                    matches: function
                )
        }?.thunk.address
    }

    private func refreshedLookup(
        in snapshot: () -> ThunkSnapshot,
        after generation: Int,
        function: FunctionTypeInfo
    ) -> UnsafeRawPointer? {
        refresh(ifUnchangedSince: generation)
        return lookup(in: snapshot().thunks, function: function)
    }

    private func refresh() {
        refresh(ifUnchangedSince: nil)
    }

    private func refresh(ifUnchangedSince expectedGeneration: Int?) {
        // Local-symbol traversal and demangling are not safe to run in
        // parallel. More than one requirement discovery can miss the same
        // snapshot while Swift Testing is constructing stubs concurrently,
        // so serialise the entire refresh rather than only merging its
        // result into the cache.
        lock.lock()
        defer { lock.unlock() }

        // A concurrent lookup may already have populated the missing thunk
        // while this caller waited for the scanner. Reuse that result instead
        // of rescanning every image for the same cache generation.
        guard refreshGeneration == expectedGeneration || expectedGeneration == nil else {
            return
        }

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
        refreshGeneration += 1
    }

    private func directToGenericSnapshot() -> ThunkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ThunkSnapshot(
            thunks: directToGenericThunks,
            generation: refreshGeneration
        )
    }

    private func genericToDirectSnapshot() -> ThunkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ThunkSnapshot(
            thunks: genericToDirectThunks,
            generation: refreshGeneration
        )
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

private struct ThunkSnapshot {
    let thunks: [DirectToGenericThunk]
    let generation: Int
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

package struct ReabstractionPair {
    package let sourceIsGeneric: Bool
    package let source: LoweredFunctionSyntax
    package let target: LoweredFunctionSyntax

    package init(
        sourceIsGeneric: Bool,
        source: LoweredFunctionSyntax,
        target: LoweredFunctionSyntax
    ) {
        self.sourceIsGeneric = sourceIsGeneric
        self.source = source
        self.target = target
    }
}

private let reabstractionPrefix =
    "partial apply forwarder for reabstraction thunk helper "

private func normalizedThunkName(_ value: String) -> String {
    let asyncPrefix = "async function pointer to "
    let withoutAsyncPrefix =
        value.hasPrefix(asyncPrefix)
        ? String(value.dropFirst(asyncPrefix.count))
        : value
    guard let suffix = withoutAsyncPrefix.range(of: " with unmangled suffix ")
    else { return withoutAsyncPrefix }
    return String(withoutAsyncPrefix[..<suffix.lowerBound])
}

private func demangleReabstractionSymbol(_ mangledName: String) -> String {
    RuntimeSymbols.demangle(mangledName)
}

/// When the thunk itself carries its own generic signature, NodePrinter.cpp
/// inserts `"<...> "` between `"helper "` and `"from "`
/// (e.g. `"...helper <A> from @callee_guaranteed (...) -> (...) to ..."`).
package func bodyAfterHelper(in demangled: Substring) -> Substring? {
    // Re-derive a String so DelimitedSyntaxScanner's indices line up with
    // `text`'s own storage -- `demangled`'s indices, taken from whatever
    // larger string it was sliced from, aren't valid offsets into a fresh
    // `String(demangled)` copy.
    let text = String(demangled)
    if text.first == "<" {
        guard let scanner = DelimitedSyntaxScanner(text),
            let closing = scanner.matchingClosingDelimiter(openingAt: text.startIndex)
        else {
            return nil
        }
        let afterGenerics = text[text.index(after: closing)...]
        guard afterGenerics.hasPrefix(" from ") else { return nil }
        return afterGenerics.dropFirst(" from ".count)
    }
    guard text.hasPrefix("from ") else { return nil }
    return text[text.index(text.startIndex, offsetBy: "from ".count)...]
}

package func reabstractionPair(in demangled: String) -> ReabstractionPair? {
    guard demangled.hasPrefix(reabstractionPrefix),
        let body = bodyAfterHelper(
            in: demangled.dropFirst(reabstractionPrefix.count)
        )
    else {
        return nil
    }
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
