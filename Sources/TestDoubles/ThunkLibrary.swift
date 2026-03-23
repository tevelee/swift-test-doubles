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
}

@inline(__always)
private func rec(_ w: UnsafeRawPointer) -> StubRecorder { MockRegistry.resolve(w) }

/// Dispatch and cast result, returning zero value in recording/verifying modes.
@inline(__always)
private func d<R>(_ w: UnsafeRawPointer, _ m: Int, _ a: [Any]) -> R {
    let r = rec(w)
    let result = r.dispatch(method: m, args: a)
    if r.mode != .normal { return zeroValue(R.self) }
    return result as! R
}

// Void dispatch
@inline(__always)
private func dv(_ w: UnsafeRawPointer, _ m: Int, _ a: [Any]) {
    let r = rec(w)
    _ = r.dispatch(method: m, args: a)
}

// --- Void getters / no-arg void methods: (selfPtr, wtPtr) -> Void ---

private let g_v_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 0, []) }
private let g_v_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 1, []) }
private let g_v_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 2, []) }
private let g_v_3: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 3, []) }
private let g_v_4: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Void = { _, w in dv(w, 4, []) }

// --- Getters: (selfPtr, wtPtr) -> T ---

private let g_i_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d(w, 0, []) }
private let g_i_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d(w, 1, []) }
private let g_i_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d(w, 2, []) }
private let g_i_3: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d(w, 3, []) }
private let g_i_4: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d(w, 4, []) }
private let g_i_5: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Int = { _, w in d(w, 5, []) }
private let g_s_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d(w, 0, []) }
private let g_s_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d(w, 1, []) }
private let g_s_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d(w, 2, []) }
private let g_s_3: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> String = { _, w in d(w, 3, []) }
private let g_b_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Bool = { _, w in d(w, 0, []) }
private let g_b_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Bool = { _, w in d(w, 1, []) }
private let g_b_2: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Bool = { _, w in d(w, 2, []) }
private let g_d_0: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Double = { _, w in d(w, 0, []) }
private let g_d_1: @convention(thin) (UnsafeRawPointer, UnsafeRawPointer) -> Double = { _, w in d(w, 1, []) }

// --- 1-arg methods ---

private let m1_si_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 0, [a]) }
private let m1_si_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 1, [a]) }
private let m1_si_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 2, [a]) }
private let m1_si_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 3, [a]) }
private let m1_ss_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 0, [a]) }
private let m1_ss_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 1, [a]) }
private let m1_ss_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 2, [a]) }
private let m1_ss_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 3, [a]) }
private let m1_ss_4: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 4, [a]) }
private let m1_ss_5: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 5, [a]) }
private let m1_sb_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, _, w in d(w, 0, [a]) }
private let m1_sb_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, _, w in d(w, 1, [a]) }
private let m1_sb_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, _, w in d(w, 2, [a]) }
private let m1_sb_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, _, w in d(w, 3, [a]) }
private let m1_sv_0: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 0, [a]) }
private let m1_sv_1: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 1, [a]) }
private let m1_sv_2: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 2, [a]) }
private let m1_sv_3: @convention(thin) (String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 3, [a]) }
private let m1_is_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 0, [a]) }
private let m1_is_1: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 1, [a]) }
private let m1_ii_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 0, [a]) }
private let m1_ii_1: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 1, [a]) }
private let m1_iv_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 0, [a]) }
private let m1_ib_0: @convention(thin) (Int, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, _, w in d(w, 0, [a]) }

// --- 2-arg methods ---

private let m2_sib_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_sib_1: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, _, w in d(w, 1, [a, b]) }
private let m2_sib_2: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, _, w in d(w, 2, [a, b]) }
private let m2_sii_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_sii_1: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d(w, 1, [a, b]) }
private let m2_sis_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_siv_0: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }
private let m2_siv_1: @convention(thin) (String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 1, [a, b]) }
private let m2_iiv_0: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }
private let m2_iii_0: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_iib_0: @convention(thin) (Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_ssb_0: @convention(thin) (String, String, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_sss_0: @convention(thin) (String, String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d(w, 0, [a, b]) }

// --- 2-arg: (Int, String) → reversed order ---

private let m2_isb_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_isi_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, b, _, w in d(w, 0, [a, b]) }
private let m2_isv_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, _, w in dv(w, 0, [a, b]) }
private let m2_iss_0: @convention(thin) (Int, String, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, b, _, w in d(w, 0, [a, b]) }

// --- 1-arg: (Bool) ---

private let m1_bv_0: @convention(thin) (Bool, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, _, w in dv(w, 0, [a]) }
private let m1_bb_0: @convention(thin) (Bool, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, _, w in d(w, 0, [a]) }
private let m1_bi_0: @convention(thin) (Bool, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 0, [a]) }

// --- 1-arg: (Double) ---

private let m1_di_0: @convention(thin) (Double, UnsafeRawPointer, UnsafeRawPointer) -> Int = { a, _, w in d(w, 0, [a]) }
private let m1_ds_0: @convention(thin) (Double, UnsafeRawPointer, UnsafeRawPointer) -> String = { a, _, w in d(w, 0, [a]) }
private let m1_dd_0: @convention(thin) (Double, UnsafeRawPointer, UnsafeRawPointer) -> Double = { a, _, w in d(w, 0, [a]) }

// --- 3-arg methods ---

private let m3_siiv_0: @convention(thin) (String, Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, c, _, w in dv(w, 0, [a, b, c]) }
private let m3_ssiv_0: @convention(thin) (String, String, Int, UnsafeRawPointer, UnsafeRawPointer) -> Void = { a, b, c, _, w in dv(w, 0, [a, b, c]) }
private let m3_siib_0: @convention(thin) (String, Int, Int, UnsafeRawPointer, UnsafeRawPointer) -> Bool = { a, b, c, _, w in d(w, 0, [a, b, c]) }

// ============================================================================
// MARK: - Thunk Catalog
// ============================================================================

public enum ThunkLibrary {
    nonisolated(unsafe) private static let catalog: [MethodSignature: [Int: UnsafeRawPointer]] = buildCatalog()

    public static func thunk(for signature: MethodSignature, slot: Int) -> UnsafeRawPointer? {
        catalog[signature]?[slot]
    }

    private static func buildCatalog() -> [MethodSignature: [Int: UnsafeRawPointer]] {
        var c = [MethodSignature: [Int: UnsafeRawPointer]]()
        func add(_ s: MethodSignature, _ slot: Int, _ p: UnsafeRawPointer) { c[s, default: [:]][slot] = p }
        func cast<T>(_ fn: T) -> UnsafeRawPointer { unsafeBitCast(fn, to: UnsafeRawPointer.self) }

        let gv = MethodSignature.getter("Void")
        for (i, fn) in [g_v_0, g_v_1, g_v_2, g_v_3, g_v_4].enumerated() { add(gv, i, cast(fn)) }
        let gi = MethodSignature.getter("Int")
        for (i, fn) in [g_i_0, g_i_1, g_i_2, g_i_3, g_i_4, g_i_5].enumerated() { add(gi, i, cast(fn)) }
        let gs = MethodSignature.getter("String")
        for (i, fn) in [g_s_0, g_s_1, g_s_2, g_s_3].enumerated() { add(gs, i, cast(fn)) }
        let gb = MethodSignature.getter("Bool")
        for (i, fn) in [g_b_0, g_b_1, g_b_2].enumerated() { add(gb, i, cast(fn)) }
        let gd = MethodSignature.getter("Double")
        for (i, fn) in [g_d_0, g_d_1].enumerated() { add(gd, i, cast(fn)) }

        let si = MethodSignature(args: ["String"], ret: "Int")
        for (i, fn) in [m1_si_0, m1_si_1, m1_si_2, m1_si_3].enumerated() { add(si, i, cast(fn)) }
        let ss = MethodSignature(args: ["String"], ret: "String")
        for (i, fn) in [m1_ss_0, m1_ss_1, m1_ss_2, m1_ss_3, m1_ss_4, m1_ss_5].enumerated() { add(ss, i, cast(fn)) }
        let sb1 = MethodSignature(args: ["String"], ret: "Bool")
        for (i, fn) in [m1_sb_0, m1_sb_1, m1_sb_2, m1_sb_3].enumerated() { add(sb1, i, cast(fn)) }
        let sv = MethodSignature(args: ["String"], ret: "Void")
        for (i, fn) in [m1_sv_0, m1_sv_1, m1_sv_2, m1_sv_3].enumerated() { add(sv, i, cast(fn)) }
        let is_ = MethodSignature(args: ["Int"], ret: "String")
        for (i, fn) in [m1_is_0, m1_is_1].enumerated() { add(is_, i, cast(fn)) }
        let ii = MethodSignature(args: ["Int"], ret: "Int")
        for (i, fn) in [m1_ii_0, m1_ii_1].enumerated() { add(ii, i, cast(fn)) }
        add(MethodSignature(args: ["Int"], ret: "Void"), 0, cast(m1_iv_0))
        add(MethodSignature(args: ["Int"], ret: "Bool"), 0, cast(m1_ib_0))

        let sib = MethodSignature(args: ["String", "Int"], ret: "Bool")
        for (i, fn) in [m2_sib_0, m2_sib_1, m2_sib_2].enumerated() { add(sib, i, cast(fn)) }
        let sii = MethodSignature(args: ["String", "Int"], ret: "Int")
        for (i, fn) in [m2_sii_0, m2_sii_1].enumerated() { add(sii, i, cast(fn)) }
        add(MethodSignature(args: ["String", "Int"], ret: "String"), 0, cast(m2_sis_0))
        let siv = MethodSignature(args: ["String", "Int"], ret: "Void")
        for (i, fn) in [m2_siv_0, m2_siv_1].enumerated() { add(siv, i, cast(fn)) }
        add(MethodSignature(args: ["Int", "Int"], ret: "Void"), 0, cast(m2_iiv_0))
        add(MethodSignature(args: ["Int", "Int"], ret: "Int"), 0, cast(m2_iii_0))
        add(MethodSignature(args: ["Int", "Int"], ret: "Bool"), 0, cast(m2_iib_0))
        add(MethodSignature(args: ["String", "String"], ret: "Bool"), 0, cast(m2_ssb_0))
        add(MethodSignature(args: ["String", "String"], ret: "String"), 0, cast(m2_sss_0))

        // 2-arg: (Int, String)
        add(MethodSignature(args: ["Int", "String"], ret: "Bool"), 0, cast(m2_isb_0))
        add(MethodSignature(args: ["Int", "String"], ret: "Int"), 0, cast(m2_isi_0))
        add(MethodSignature(args: ["Int", "String"], ret: "Void"), 0, cast(m2_isv_0))
        add(MethodSignature(args: ["Int", "String"], ret: "String"), 0, cast(m2_iss_0))

        // 1-arg: (Bool)
        add(MethodSignature(args: ["Bool"], ret: "Void"), 0, cast(m1_bv_0))
        add(MethodSignature(args: ["Bool"], ret: "Bool"), 0, cast(m1_bb_0))
        add(MethodSignature(args: ["Bool"], ret: "Int"), 0, cast(m1_bi_0))

        // 1-arg: (Double)
        add(MethodSignature(args: ["Double"], ret: "Int"), 0, cast(m1_di_0))
        add(MethodSignature(args: ["Double"], ret: "String"), 0, cast(m1_ds_0))
        add(MethodSignature(args: ["Double"], ret: "Double"), 0, cast(m1_dd_0))

        add(MethodSignature(args: ["String", "Int", "Int"], ret: "Void"), 0, cast(m3_siiv_0))
        add(MethodSignature(args: ["String", "String", "Int"], ret: "Void"), 0, cast(m3_ssiv_0))
        add(MethodSignature(args: ["String", "Int", "Int"], ret: "Bool"), 0, cast(m3_siib_0))

        return c
    }
}
