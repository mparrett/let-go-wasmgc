# FINDINGS (things learned that are not decisions; candidates for later, generic upstream reports)

## Hashing (from corpus/hash/SPEC.md, let-go 4e769212, 2026-09-30)
- H1. `hashOrdered` counts EmptyList as one nil element, so `()`, `(nil)`, `[nil]` and an empty PersistentVector all hash alike, while an empty ArrayVector hashes differently: `(= [] ())` is true but `(contains? #{[]} ())` is false. Looks like a real bug.
- H2. Float hashing does not fold -0.0 into 0.0: `(= 0.0 -0.0)` is true, hashes differ, `(get {0.0 :z} -0.0)` depends on map size. Looks like a real bug.
- H3. Map entries hash as `hash(k) ^ hash(v)`; a map whose keys equal their values hashes to 0, same as `{}`, `#{}`, nil, false, 0, 0.0. Weak, not wrong.
- H4. Int/Char/Float/in-range BigInt share one finalizer: `97` = `\a`, `1` = `1N`, `MinInt64` = `-0.0`; `0.1M` = `0.1`; keyword hash = symbol hash + 0x9e3779b9.
- H5. `hashUnordered` has no callers; legacy `vm.Map` has no Hash() and falls back to FNV of its printed form (Go map order). Not reader-producible.

## Arithmetic (from corpus/opmatrix, D16)
- A1. `(quot MinInt64 -1)` and `(- MinInt64)` wrap silently while sibling forms throw; overflow and divide-by-zero error strings are inconsistently prefixed. Parity for now.

## IR pipeline (from the 2a census)
- I1. Two LICM validation failures on xsofy (`read-dismiss-key!`, `bfs-path`).
- I2. Every structurize fallback on both corpora is the multi-exit loop case.
- I3. lower-go reports "unsupported function body shape" on the probe's `fibl` loop.

## let-go runtime oddities met while writing the reference intrinsics (2026-10-01)
- R1. `(not= ##NaN ##NaN)` is false, so `not=` is not `(not (= …))` for NaN.
- R2. `ns-resolve` returns nil even for public vars; core vars carry no `:ns` meta.
- R3. `bit-or` takes exactly 2 args.
- R4. Shifts follow Go (count not masked): `(bit-shift-right -8 64)` = -1. The wasm backend masks mod 64; the reference intrinsics mirror wasm, lg's own ops mirror lg (D16).
