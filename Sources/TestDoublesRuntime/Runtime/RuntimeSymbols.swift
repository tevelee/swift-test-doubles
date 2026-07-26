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
        withLock {
            if let cached = runtimeTypes[name] {
                return cached
            }
            guard let resolved = resolve() else { return nil }
            runtimeTypes[name] = resolved
            return resolved
        }
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
