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
        guard let result else { return mangledName }
        withLock { demangledNames[mangledName] = result }
        return result
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
