/// Describes a method signature for thunk lookup.
public struct MethodSignature: Hashable, Sendable {
    public let args: [String]
    public let ret: String

    public init(args: [String], ret: String) {
        self.args = args
        self.ret = ret
    }

    public static func getter(_ type: String) -> MethodSignature { .init(args: [], ret: type) }
    public static func method(_ args: [String], returning ret: String) -> MethodSignature { .init(args: args, ret: ret) }

    /// Maps this signature to its ABI-class equivalent for thunk lookup.
    var abiSignature: MethodSignature {
        MethodSignature(args: args.map(argABI), ret: retABI(ret))
    }
}

// MARK: - ABI Class Mapping
//
// Only 3 ABI classes needed for thunk signatures:
// - "W1" (Int): covers ALL 8-byte types (Int, Bool, Double, Array, class refs, custom structs)
// - "W2" (String): covers 16-byte types
// - "V" (Void): covers void returns and void methods
//
// The ARC distinction (retain for reference types) is handled in the dispatch
// function, not by having separate thunks.

private func argABI(_ typeName: String) -> String {
    switch typeName {
    case "Void": return "V"
    case "String": return "W2"
    default: return "W1"
    }
}

private func retABI(_ typeName: String) -> String {
    switch typeName {
    case "Void": return "V"
    case "String": return "W2"
    default: return "W1"
    }
}

/// Determines if a return type needs ARC retain when returned as raw bits.
func isReferenceReturn(_ typeName: String) -> Bool {
    if typeName.hasPrefix("[") || typeName.hasPrefix("Array<")
        || typeName.hasPrefix("Set<") || typeName.hasPrefix("Dictionary<") {
        return true
    }
    // Known value types
    switch typeName {
    case "Int", "Bool", "Double", "Float", "String", "Void",
         "UInt", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64":
        return false
    default:
        // Unknown types: conservatively assume reference.
        // Over-retaining causes a leak but not a crash; under-retaining crashes.
        return true
    }
}

// MARK: - Dispatch Functions

@inline(__always)
private func rec(_ w: UnsafeRawPointer) -> StubRecorder { MockRegistry.resolve(w) }

/// W1 dispatch: extracts 8-byte value from Any, retains if reference type.
@inline(__always)
private func d1(_ w: UnsafeRawPointer, _ m: Int, _ a: [Any]) -> Int {
    let r = rec(w)
    let result = r.dispatch(method: m, args: a)
    if r.mode != .normal { return 0 }
    let word = withUnsafePointer(to: result) { UnsafeRawPointer($0).load(as: Int.self) }
    if r.isRefReturn(m), let rawPtr = UnsafeRawPointer(bitPattern: word) {
        _ = Unmanaged<AnyObject>.fromOpaque(rawPtr).retain()
    }
    return word
}

/// W2 dispatch: String return (type-safe cast).
@inline(__always)
private func d2(_ w: UnsafeRawPointer, _ m: Int, _ a: [Any]) -> String {
    let r = rec(w)
    let result = r.dispatch(method: m, args: a)
    if r.mode != .normal { return "" }
    return result as! String
}

/// V dispatch: Void return.
@inline(__always)
private func dv(_ w: UnsafeRawPointer, _ m: Int, _ a: [Any]) {
    let r = rec(w)
    _ = r.dispatch(method: m, args: a)
}

// MARK: - Thunks
//
// Minimal set: 3 return types × 3 arg types × N slots per arity.
// Total: ~120 thunks covering 0-3 args, 8 slots each.

private let maxSlots = 8

// --- Getters: (selfPtr, wtPtr) -> T ---

// W1 getters (all 8-byte returns: Int, Bool, Double, Array, class refs...)
private let g1_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 0, []) }
private let g1_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 1, []) }
private let g1_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 2, []) }
private let g1_3: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 3, []) }
private let g1_4: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 4, []) }
private let g1_5: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 5, []) }
private let g1_6: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 6, []) }
private let g1_7: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d1(w, 7, []) }

// W2 getters (String)
private let g2_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 0, []) }
private let g2_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 1, []) }
private let g2_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 2, []) }
private let g2_3: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 3, []) }
private let g2_4: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 4, []) }
private let g2_5: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 5, []) }
private let g2_6: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 6, []) }
private let g2_7: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d2(w, 7, []) }

// V getters (Void)
private let gv_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 0, []) }
private let gv_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 1, []) }
private let gv_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 2, []) }
private let gv_3: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 3, []) }
private let gv_4: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 4, []) }
private let gv_5: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 5, []) }
private let gv_6: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 6, []) }
private let gv_7: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 7, []) }

// --- 1-arg: (W1, ptr, ptr) -> T ---

private let m1_11_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 0, [a]) }
private let m1_11_1: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 1, [a]) }
private let m1_11_2: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 2, [a]) }
private let m1_11_3: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 3, [a]) }
private let m1_11_4: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 4, [a]) }
private let m1_11_5: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 5, [a]) }
private let m1_11_6: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 6, [a]) }
private let m1_11_7: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 7, [a]) }

private let m1_12_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 0, [a]) }
private let m1_12_1: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 1, [a]) }
private let m1_12_2: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 2, [a]) }
private let m1_12_3: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 3, [a]) }

private let m1_1v_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 0, [a]) }
private let m1_1v_1: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 1, [a]) }
private let m1_1v_2: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 2, [a]) }
private let m1_1v_3: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 3, [a]) }

// --- 1-arg: (W2, ptr, ptr) -> T ---

private let m1_21_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 0, [a]) }
private let m1_21_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 1, [a]) }
private let m1_21_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 2, [a]) }
private let m1_21_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 3, [a]) }
private let m1_21_4: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 4, [a]) }
private let m1_21_5: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d1(w, 5, [a]) }

private let m1_22_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 0, [a]) }
private let m1_22_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 1, [a]) }
private let m1_22_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 2, [a]) }
private let m1_22_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 3, [a]) }
private let m1_22_4: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 4, [a]) }
private let m1_22_5: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d2(w, 5, [a]) }

private let m1_2v_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 0, [a]) }
private let m1_2v_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 1, [a]) }
private let m1_2v_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 2, [a]) }
private let m1_2v_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 3, [a]) }

// --- 2-arg: (W1, W1, ptr, ptr) -> T ---

private let m2_111_0: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 0, [a, b]) }
private let m2_111_1: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 1, [a, b]) }
private let m2_111_2: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 2, [a, b]) }
private let m2_111_3: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 3, [a, b]) }

private let m2_112_0: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d2(w, 0, [a, b]) }
private let m2_11v_0: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }
private let m2_11v_1: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 1, [a, b]) }

// --- 2-arg: (W2, W1, ptr, ptr) -> T ---

private let m2_211_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 0, [a, b]) }
private let m2_211_1: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 1, [a, b]) }
private let m2_211_2: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 2, [a, b]) }

private let m2_212_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d2(w, 0, [a, b]) }
private let m2_21v_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }
private let m2_21v_1: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 1, [a, b]) }

// --- 2-arg: (W1, W2, ptr, ptr) -> T ---

private let m2_121_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 0, [a, b]) }
private let m2_122_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d2(w, 0, [a, b]) }
private let m2_12v_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }

// --- 2-arg: (W2, W2, ptr, ptr) -> T ---

private let m2_221_0: @convention(thin) (String, String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d1(w, 0, [a, b]) }
private let m2_222_0: @convention(thin) (String, String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d2(w, 0, [a, b]) }
private let m2_22v_0: @convention(thin) (String, String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }

// --- 3-arg: (W2, W1, W1, ptr, ptr) -> T ---

private let m3_2111_0: @convention(thin) (String, Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, c, _, w in d1(w, 0, [a, b, c]) }
private let m3_211v_0: @convention(thin) (String, Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, c, _, w in dv(w, 0, [a, b, c]) }

// --- 3-arg: (W2, W2, W1, ptr, ptr) -> T ---

private let m3_2211_0: @convention(thin) (String, String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, c, _, w in d1(w, 0, [a, b, c]) }
private let m3_221v_0: @convention(thin) (String, String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, c, _, w in dv(w, 0, [a, b, c]) }

// --- 3-arg: (W1, W1, W1, ptr, ptr) -> T ---

private let m3_1111_0: @convention(thin) (Int, Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, c, _, w in d1(w, 0, [a, b, c]) }
private let m3_111v_0: @convention(thin) (Int, Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, c, _, w in dv(w, 0, [a, b, c]) }

// ============================================================================
// MARK: - Thunk Catalog
// ============================================================================

public enum ThunkLibrary {
    nonisolated(unsafe) private static let catalog: [MethodSignature: [Int: UnsafeRawPointer]] = buildCatalog()

    /// Look up a thunk. Maps the signature to its ABI class first.
    public static func thunk(for signature: MethodSignature, slot: Int) -> UnsafeRawPointer? {
        catalog[signature.abiSignature]?[slot]
    }

    private static func buildCatalog() -> [MethodSignature: [Int: UnsafeRawPointer]] {
        var c = [MethodSignature: [Int: UnsafeRawPointer]]()
        func add(_ s: MethodSignature, _ slot: Int, _ p: UnsafeRawPointer) { c[s, default: [:]][slot] = p }
        func cast<T>(_ fn: T) -> UnsafeRawPointer { unsafeBitCast(fn, to: UnsafeRawPointer.self) }

        // Getters
        for (i, fn) in [g1_0, g1_1, g1_2, g1_3, g1_4, g1_5, g1_6, g1_7].enumerated() {
            add(.getter("W1"), i, cast(fn))
        }
        for (i, fn) in [g2_0, g2_1, g2_2, g2_3, g2_4, g2_5, g2_6, g2_7].enumerated() {
            add(.getter("W2"), i, cast(fn))
        }
        for (i, fn) in [gv_0, gv_1, gv_2, gv_3, gv_4, gv_5, gv_6, gv_7].enumerated() {
            add(.getter("V"), i, cast(fn))
        }

        // 1-arg: W1 -> {W1, W2, V}
        for (i, fn) in [m1_11_0, m1_11_1, m1_11_2, m1_11_3, m1_11_4, m1_11_5, m1_11_6, m1_11_7].enumerated() {
            add(.init(args: ["W1"], ret: "W1"), i, cast(fn))
        }
        for (i, fn) in [m1_12_0, m1_12_1, m1_12_2, m1_12_3].enumerated() {
            add(.init(args: ["W1"], ret: "W2"), i, cast(fn))
        }
        for (i, fn) in [m1_1v_0, m1_1v_1, m1_1v_2, m1_1v_3].enumerated() {
            add(.init(args: ["W1"], ret: "V"), i, cast(fn))
        }

        // 1-arg: W2 -> {W1, W2, V}
        for (i, fn) in [m1_21_0, m1_21_1, m1_21_2, m1_21_3, m1_21_4, m1_21_5].enumerated() {
            add(.init(args: ["W2"], ret: "W1"), i, cast(fn))
        }
        for (i, fn) in [m1_22_0, m1_22_1, m1_22_2, m1_22_3, m1_22_4, m1_22_5].enumerated() {
            add(.init(args: ["W2"], ret: "W2"), i, cast(fn))
        }
        for (i, fn) in [m1_2v_0, m1_2v_1, m1_2v_2, m1_2v_3].enumerated() {
            add(.init(args: ["W2"], ret: "V"), i, cast(fn))
        }

        // 2-arg: W1, W1
        for (i, fn) in [m2_111_0, m2_111_1, m2_111_2, m2_111_3].enumerated() {
            add(.init(args: ["W1", "W1"], ret: "W1"), i, cast(fn))
        }
        add(.init(args: ["W1", "W1"], ret: "W2"), 0, cast(m2_112_0))
        for (i, fn) in [m2_11v_0, m2_11v_1].enumerated() {
            add(.init(args: ["W1", "W1"], ret: "V"), i, cast(fn))
        }

        // 2-arg: W2, W1
        for (i, fn) in [m2_211_0, m2_211_1, m2_211_2].enumerated() {
            add(.init(args: ["W2", "W1"], ret: "W1"), i, cast(fn))
        }
        add(.init(args: ["W2", "W1"], ret: "W2"), 0, cast(m2_212_0))
        for (i, fn) in [m2_21v_0, m2_21v_1].enumerated() {
            add(.init(args: ["W2", "W1"], ret: "V"), i, cast(fn))
        }

        // 2-arg: W1, W2
        add(.init(args: ["W1", "W2"], ret: "W1"), 0, cast(m2_121_0))
        add(.init(args: ["W1", "W2"], ret: "W2"), 0, cast(m2_122_0))
        add(.init(args: ["W1", "W2"], ret: "V"), 0, cast(m2_12v_0))

        // 2-arg: W2, W2
        add(.init(args: ["W2", "W2"], ret: "W1"), 0, cast(m2_221_0))
        add(.init(args: ["W2", "W2"], ret: "W2"), 0, cast(m2_222_0))
        add(.init(args: ["W2", "W2"], ret: "V"), 0, cast(m2_22v_0))

        // 3-arg
        add(.init(args: ["W2", "W1", "W1"], ret: "W1"), 0, cast(m3_2111_0))
        add(.init(args: ["W2", "W1", "W1"], ret: "V"), 0, cast(m3_211v_0))
        add(.init(args: ["W2", "W2", "W1"], ret: "W1"), 0, cast(m3_2211_0))
        add(.init(args: ["W2", "W2", "W1"], ret: "V"), 0, cast(m3_221v_0))
        add(.init(args: ["W1", "W1", "W1"], ret: "W1"), 0, cast(m3_1111_0))
        add(.init(args: ["W1", "W1", "W1"], ret: "V"), 0, cast(m3_111v_0))

        return c
    }
}
