import CTestDoublesTrampoline
import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Android)
    import Android
#elseif canImport(Glibc)
    import Glibc
#endif

/// Process-wide runtime symbol access.
///
/// Successful lookups are stable for the lifetime of the process and are
/// cached. Misses are deliberately retried so images loaded later can supply
/// metadata, runtime entry points, or compiler-emitted thunks.
package enum RuntimeSymbols {
    private struct SymbolNameKey: Hashable {
        let address: UInt
        let exact: Bool
    }

    private struct Address: @unchecked Sendable {
        let value: UnsafeMutableRawPointer
    }

    private struct Handle: @unchecked Sendable {
        let value: UnsafeMutableRawPointer?
    }

    #if !os(WASI)
        private static let handle = Handle(value: dlopen(nil, RTLD_NOW))
    #endif
    private static let lock = NSLock()
    // The C fallback walks loaded images. Keep only that walk serial: it has
    // process-wide loader state, while holding `lock` across a Swift runtime
    // query can invert the runtime's own locks under concurrent fabrication.
    private static let symbolLookupLock = NSLock()
    private nonisolated(unsafe) static var addresses: [String: Address] = [:]
    private nonisolated(unsafe) static var symbolNames: [SymbolNameKey: String] = [:]
    private nonisolated(unsafe) static var demangledNames: [String: String] = [:]
    private nonisolated(unsafe) static var runtimeTypes: [String: Any.Type] = [:]

    package static func rawSymbol(named name: String) -> UnsafeMutableRawPointer? {
        if let cached = withLock({ addresses[name] }) {
            return cached.value
        }
        let address = name.withCString { symbol in
            #if os(WASI)
                fallbackSymbolAddress(symbol)
            #else
                handle.value.flatMap { dlsym($0, symbol) }
                    ?? fallbackSymbolAddress(symbol)
            #endif
        }
        guard let address else { return nil }
        withLock { addresses[name] = Address(value: address) }
        return address
    }

    /// Returns the next process-global monotonic invocation sequence number.
    package static func nextGlobalInvocationSequence() -> UInt64 {
        td_next_global_invocation_sequence()
    }

    package static func function<Function>(
        named name: String,
        as _: Function.Type = Function.self
    ) -> Function? {
        rawSymbol(named: name).map { unsafeBitCast($0, to: Function.self) }
    }

    package static func symbolName(
        at address: UnsafeRawPointer,
        exact: Bool = false
    ) -> String? {
        cachedSymbolName(at: address, exact: exact) {
            let symbol =
                exact
                ? td_exact_symbol_name(address)
                : td_symbol_name(address)
            return symbol.map { String(cString: $0) }
        }
    }

    /// Exposes the cache boundary separately so tests can prove that successful
    /// lookups are reused while misses remain retryable.
    package static func cachedSymbolName(
        at address: UnsafeRawPointer,
        exact: Bool = false,
        resolve: () -> String?
    ) -> String? {
        let key = SymbolNameKey(
            address: UInt(bitPattern: address),
            exact: exact
        )
        if let cached = withLock({ symbolNames[key] }) {
            return cached
        }
        guard let resolved = resolve() else { return nil }
        withLock { symbolNames[key] = resolved }
        return resolved
    }

    package static func demangle(_ mangledName: String) -> String {
        if let cached = withLock({ demangledNames[mangledName] }) {
            return cached
        }
        let directlyDemangled = swiftDemangledName(mangledName)
        let result =
            if directlyDemangled == mangledName {
                demangleCoroutinePointerCompatibilitySymbol(mangledName)
                    ?? demangleNonsendingCompatibilitySymbol(mangledName)
                    ?? demangleImplicitActorCompatibilitySymbol(mangledName)
                    ?? demangleIsolatedParameterCompatibilitySymbol(mangledName)
                    ?? directlyDemangled
            } else {
                directlyDemangled
            }
        withLock { demangledNames[mangledName] = result }
        return result
    }

    private static func swiftDemangledName(_ mangledName: String) -> String {
        let result: String? = mangledName.utf8CString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress,
                let demangled = swiftDemangle(
                    baseAddress,
                    buffer.count - 1,
                    nil,
                    nil,
                    0
                )
            else {
                return nil
            }
            defer { free(demangled) }
            return String(cString: demangled)
        }
        return result ?? mangledName
    }

    /// Bridges Swift 6.3's coroutine-function-pointer suffix when the process
    /// runtime's demangler understands the witness but not its pointer wrapper.
    private static func demangleCoroutinePointerCompatibilitySymbol(
        _ mangledName: String
    ) -> String? {
        let suffix = "Twc"
        guard mangledName.hasSuffix(suffix) else { return nil }
        let witnessName = String(mangledName.dropLast(suffix.count))
        let witnessDemangling = swiftDemangledName(witnessName)
        guard witnessDemangling != witnessName else { return nil }
        return "coro function pointer to \(witnessDemangling)"
    }

    /// Bridges Swift 6.3 `nonisolated(nonsending)` symbols when the process
    /// runtime's demangler predates that mangling node.
    private static func demangleNonsendingCompatibilitySymbol(
        _ mangledName: String
    ) -> String? {
        guard mangledName.contains("YC") else { return nil }

        let isolatedSurrogate = mangledName.replacingOccurrences(
            of: "YC",
            with: "YA"
        )
        let plainSurrogate = mangledName.replacingOccurrences(
            of: "YC",
            with: ""
        )
        let isolatedDemangling = swiftDemangledName(isolatedSurrogate)
        let plainDemangling = swiftDemangledName(plainSurrogate)
        guard isolatedDemangling != isolatedSurrogate,
            plainDemangling != plainSurrogate
        else {
            return nil
        }

        return replacingInsertedOccurrences(
            [
                (
                    marker: "@isolated(any) ",
                    replacement: "nonisolated(nonsending) "
                )
            ],
            in: isolatedDemangling,
            relativeTo: plainDemangling
        )
    }

    /// Bridges Swift 6.3's lowered `Builtin.ImplicitActor` parameter when the
    /// process runtime's demangler predates that builtin mangling.
    private static func demangleImplicitActorCompatibilitySymbol(
        _ mangledName: String
    ) -> String? {
        guard mangledName.contains("BA"),
            mangledName.contains("gIL")
        else {
            return nil
        }

        let nativeObjectSurrogate =
            mangledName
            .replacingOccurrences(of: "BA", with: "Bo")
            .replacingOccurrences(of: "gIL", with: "g")
        let plainSurrogate =
            mangledName
            .replacingOccurrences(of: "BA", with: "")
            .replacingOccurrences(of: "gIL", with: "")
        let nativeObjectDemangling = swiftDemangledName(nativeObjectSurrogate)
        let plainDemangling = swiftDemangledName(plainSurrogate)
        guard nativeObjectDemangling != nativeObjectSurrogate,
            plainDemangling != plainSurrogate
        else {
            return nil
        }

        return replacingInsertedOccurrences(
            [
                (
                    marker: "@guaranteed Builtin.NativeObject, ",
                    replacement: "@guaranteed Builtin.ImplicitActor, "
                ),
                (
                    marker: "@guaranteed Builtin.NativeObject",
                    replacement: "@guaranteed Builtin.ImplicitActor"
                )
            ],
            in: nativeObjectDemangling,
            relativeTo: plainDemangling
        )
    }

    /// Bridges Swift 6.3's lowered isolated-parameter flag when the process
    /// runtime's demangler predates that convention marker.
    private static func demangleIsolatedParameterCompatibilitySymbol(
        _ mangledName: String
    ) -> String? {
        guard mangledName.contains("gI") || mangledName.contains("nI") else {
            return nil
        }

        let sendingSurrogate =
            mangledName
            .replacingOccurrences(of: "gI", with: "gT")
            .replacingOccurrences(of: "nI", with: "nT")
        let plainSurrogate =
            mangledName
            .replacingOccurrences(of: "gI", with: "g")
            .replacingOccurrences(of: "nI", with: "n")
        let sendingDemangling = swiftDemangledName(sendingSurrogate)
        let plainDemangling = swiftDemangledName(plainSurrogate)
        guard sendingDemangling != sendingSurrogate,
            plainDemangling != plainSurrogate
        else {
            return nil
        }

        return replacingInsertedOccurrences(
            [(marker: "sending ", replacement: "isolated ")],
            in: sendingDemangling,
            relativeTo: plainDemangling
        )
    }

    /// Replaces only marker occurrences added to `marked`, leaving matching
    /// occurrences already present in `unmarked` untouched.
    private static func replacingInsertedOccurrences(
        _ replacements: [(marker: String, replacement: String)],
        in marked: String,
        relativeTo unmarked: String
    ) -> String? {
        var markedIndex = marked.startIndex
        var unmarkedIndex = unmarked.startIndex
        var result = ""

        while markedIndex < marked.endIndex {
            let markedRemainder = marked[markedIndex...]
            let unmarkedRemainder = unmarked[unmarkedIndex...]
            if let inserted = replacements.first(where: {
                markedRemainder.hasPrefix($0.marker)
                    && unmarkedRemainder.hasPrefix($0.marker) == false
            }) {
                result += inserted.replacement
                markedIndex = marked.index(
                    markedIndex,
                    offsetBy: inserted.marker.count
                )
                continue
            }
            guard unmarkedIndex < unmarked.endIndex,
                marked[markedIndex] == unmarked[unmarkedIndex]
            else {
                return nil
            }
            result.append(marked[markedIndex])
            marked.formIndex(after: &markedIndex)
            unmarked.formIndex(after: &unmarkedIndex)
        }

        return unmarkedIndex == unmarked.endIndex ? result : nil
    }

    package static func cachedRuntimeType(
        named name: String,
        resolve: () -> Any.Type?
    ) -> Any.Type? {
        if let cached = withLock({ runtimeTypes[name] }) {
            return cached
        }

        // Resolution can recursively ask for component metadata. Only protect
        // the cache itself: holding `lock` while resolving would deadlock that
        // nested lookup and can also invert Swift runtime locks.
        guard let resolved = resolve() else { return nil }
        withLock { runtimeTypes[name] = resolved }
        return resolved
    }

    private static func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private static func fallbackSymbolAddress(_ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer? {
        symbolLookupLock.lock()
        defer { symbolLookupLock.unlock() }
        return td_symbol_address(symbol).map(UnsafeMutableRawPointer.init(mutating:))
    }
}

@_silgen_name("swift_demangle")
private func swiftDemangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
