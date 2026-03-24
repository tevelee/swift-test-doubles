import Foundation

// ============================================================================
// Mock Bridge — @_cdecl entry points called by runtime-compiled dylibs
//
// The compiled mock types use @_silgen_name to resolve these symbols
// from the host process via -undefined dynamic_lookup.
// ============================================================================

/// Dispatch returning an 8-byte value (Int, Bool, Double, etc.)
@_cdecl("td_bridge_dispatch_int")
public func td_bridge_dispatch_int(_ ctx: UnsafeRawPointer, _ method: Int32) -> Int {
    let recorder = MockRegistry.resolve(ctx)
    let result = recorder.dispatch(method: Int(method), args: [])
    if recorder.mode != .normal { return 0 }
    return withUnsafePointer(to: result) { UnsafeRawPointer($0).load(as: Int.self) }
}

/// Dispatch returning a heap-allocated C string (caller must free).
@_cdecl("td_bridge_dispatch_string")
public func td_bridge_dispatch_string(_ ctx: UnsafeRawPointer, _ method: Int32) -> UnsafeMutablePointer<CChar>? {
    let recorder = MockRegistry.resolve(ctx)
    let result = recorder.dispatch(method: Int(method), args: [])
    if recorder.mode != .normal { return strdup("") }
    return strdup((result as? String) ?? "")
}

/// 1-arg String dispatch returning String.
@_cdecl("td_bridge_dispatch_s_s")
public func td_bridge_dispatch_s_s(_ ctx: UnsafeRawPointer, _ method: Int32, _ a: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    let recorder = MockRegistry.resolve(ctx)
    let result = recorder.dispatch(method: Int(method), args: [String(cString: a)])
    if recorder.mode != .normal { return strdup("") }
    return strdup((result as? String) ?? "")
}

/// 1-arg Int dispatch returning Int.
@_cdecl("td_bridge_dispatch_i_i")
public func td_bridge_dispatch_i_i(_ ctx: UnsafeRawPointer, _ method: Int32, _ a: Int) -> Int {
    let recorder = MockRegistry.resolve(ctx)
    let result = recorder.dispatch(method: Int(method), args: [a])
    if recorder.mode != .normal { return 0 }
    return withUnsafePointer(to: result) { UnsafeRawPointer($0).load(as: Int.self) }
}

/// Check if a method should throw. Returns 1 if should throw, 0 otherwise.
/// If returning 1, the error pointer is written to the provided location.
@_cdecl("td_bridge_should_throw")
public func td_bridge_should_throw(_ ctx: UnsafeRawPointer, _ method: Int32) -> Int {
    let recorder = MockRegistry.resolve(ctx)
    guard let entries = recorder.throwingStubs[Int(method)] else { return 0 }
    // If there's a throwing stub, try it
    for entry in entries {
        do {
            _ = try entry.handler([])
            return 0 // stub succeeded, don't throw
        } catch {
            // Store the error in a thread-local for the generated code to retrieve
            Thread.current.threadDictionary["_td_last_error"] = error
            return 1
        }
    }
    return 0
}

/// Retrieve the last stored error (from td_bridge_should_throw).
@_cdecl("td_bridge_get_error")
public func td_bridge_get_error() -> NSError {
    let error = Thread.current.threadDictionary["_td_last_error"]
    Thread.current.threadDictionary["_td_last_error"] = nil
    return (error as? NSError) ?? NSError(domain: "TestDoubles", code: -1)
}
